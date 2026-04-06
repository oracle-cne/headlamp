#! /bin/bash

set -eE
set -x


if ! which ocne; then
	if [ -z "$HEADLAMP_SKIP_INSTALL_DEPS" ]; then
		sudo dnf install -y ocne
	else
		echo "The ocne cli is required"
		exit 1
	fi
fi

if ! which podman; then
	if [ -z "$HEADLAMP_SKIP_INSTALL_DEPS" ]; then
		sudo dnf install -y podman
	else
		echo "podman is required"
		exit 1
	fi
fi

if ! which kubectl; then
	if [ -z "$HEADLAMP_SKIP_INSTALL_DEPS" ]; then
		sudo dnf install -y kubectl
	else
		echo "kubectl is required"
		exit 1
	fi
fi

if ! which openssl; then
	if [ -z "$HEADLAMP_SKIP_INSTALL_DEPS" ]; then
		sudo dnf install -y openssl
	else
		echo "openssl is required"
		exit 1
	fi
fi

if ! which virsh; then
	if [ -z "$HEADLAMP_SKIP_INSTALL_DEPS" ]; then
		if [ -f /etc/os-release ]; then
			os_id=$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"')
			os_version_id=$(sed -n 's/^VERSION_ID=//p' /etc/os-release | tr -d '"')
			os_major_version=${os_version_id%%.*}

			if [ "$os_id" = "ol" ] && [ "$os_major_version" = "8" ]; then
				dnf install -y oracle-ocne-release-el8 oraclelinux-developer-release-el8 oracle-epel-release-el8
				dnf config-manager --enable ol8_kvm_appstream ol8_UEKR7 ol8_ocne ol8_developer_EPEL ol8_olcne19 ol8_codeready_builder

				dnf module reset virt:ol
				dnf module install -y virt:kvm_utils3/common

				if [ -z "$(rpm -qa podman)" ]; then
					dnf install -y podman
				fi


				# Fix up an issue with libvirt and XATTR in containers
				sed -i 's/#remember_owner = 1/remember_owner = 0/g' /etc/libvirt/qemu.conf
				sed -i 's/#namespaces = .*/namespaces = []/g' /etc/libvirt/qemu.conf

				if [ ! -e /dev/kvm ] && [ -n "$KVM_MINOR" ]; then
					mknod /dev/kvm c 10 $KVM_MINOR
				fi

				systemctl enable --now libvirtd.service

			fi
		fi
	fi
fi

export HEADLAMP_CLUSTER_NAME=headlamp-test
export IMG_NAME="container-registry.oracle.com/olcne/ui"
export TAG="v0.41.0"
ui_selector="app.kubernetes.io/name=ui"
delete_ocne_cluster=false
test_started=false

if [ -z "${KUBECONFIG:-}" ]; then
	delete_ocne_cluster=true
	ocne cluster start --auto-start-ui=false -C "$HEADLAMP_CLUSTER_NAME"
	export KUBECONFIG
	KUBECONFIG=$(ocne cluster show -C "$HEADLAMP_CLUSTER_NAME")
fi

cluster_nodes=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

if [ -z "$cluster_nodes" ]; then
	echo "Unable to determine the cluster nodes from the current KUBECONFIG"
	exit 1
fi

for cluster_node in $cluster_nodes; do
	podman save "${IMG_NAME}:${TAG}" | ocne cluster console --direct --node "$cluster_node" -- podman load
	ocne cluster console --direct --node "$cluster_node" -- podman tag "${IMG_NAME}:${TAG}" "${IMG_NAME}:current"
done

report_test_failure() {
	if [ "$test_started" != true ]; then
		return
	fi

	trap - ERR
	set +e

	echo "Test failed; collecting cluster diagnostics"
	kubectl get nodes -o wide || true
	kubectl get pods -n ocne-system -l "$ui_selector" -o wide || true
	kubectl describe pods -n ocne-system -l "$ui_selector" || true

	exit 1
}

trap report_test_failure ERR

test_started=true
kubectl delete pod -n ocne-system -l "$ui_selector"

ui_pod=""
for _ in $(seq 1 24); do
	ui_pod=$(
		kubectl get pods -n ocne-system -l "$ui_selector" \
			-o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.deletionTimestamp}{"\n"}{end}' |
			awk '$2 == "" { print $1; exit }'
	)

	if [ -n "$ui_pod" ]; then
		break
	fi

	sleep 5
done

if [ -z "$ui_pod" ]; then
	echo "Timed out waiting for the UI pod to be recreated in ocne-system"
	exit 1
fi

kubectl wait --namespace ocne-system --for=jsonpath='{.status.phase}'=Running "pod/${ui_pod}" --timeout=120s
kubectl wait --namespace ocne-system --for=condition=Ready "pod/${ui_pod}" --timeout=120s

ui_service=$(
	kubectl get service -n ocne-system -o go-template='{{range .items}}{{.metadata.name}}{{"\t"}}{{with .spec.selector}}{{index . "app.kubernetes.io/name"}}{{end}}{{"\n"}}{{end}}' |
		awk '$2 == "ui" { print $1; exit }'
)

if [ -z "$ui_service" ]; then
	echo "Unable to find the UI service in ocne-system"
	exit 1
fi

ui_service_port=$(kubectl get service "$ui_service" -n ocne-system -o jsonpath='{.spec.ports[0].port}')

if [ -z "$ui_service_port" ]; then
	echo "Unable to determine the UI service port in ocne-system"
	exit 1
fi

tmpdir=$(mktemp -d)
port_forward_pid=""

cleanup() {
	status=$?
	trap - EXIT

	if [ -n "$port_forward_pid" ] && kill -0 "$port_forward_pid" 2>/dev/null; then
		kill "$port_forward_pid"
		wait "$port_forward_pid" 2>/dev/null || true
	fi

	rm -rf "$tmpdir"

	if [ "$delete_ocne_cluster" = true ]; then
		ocne cluster delete -c "${HEADLAMP_CLUSTER_NAME}" || status=$?
	fi

	exit "$status"
}

trap cleanup EXIT

ui_secret_cert=$(kubectl get secret ui-tls -n ocne-system -o jsonpath='{.data.tls\.crt}')
if [ -z "$ui_secret_cert" ]; then
	echo "Unable to read tls.crt from secret ui-tls in ocne-system"
	exit 1
fi

printf '%s' "$ui_secret_cert" | base64 -d > "${tmpdir}/ui-secret-full.pem"
openssl x509 -in "${tmpdir}/ui-secret-full.pem" -out "${tmpdir}/ui-secret.crt"

ui_ca_cert=$(kubectl get secret certificate-authority-tls -n ocne-system -o jsonpath='{.data.tls\.crt}')
if [ -z "$ui_ca_cert" ]; then
	ui_ca_cert=$(kubectl get secret certificate-authority-tls -n ocne-system -o jsonpath='{.data.ca\.crt}')
fi

if [ -n "$ui_ca_cert" ]; then
	printf '%s' "$ui_ca_cert" | base64 -d > "${tmpdir}/ui-ca.crt"
fi

if [ ! -s "${tmpdir}/ui-ca.crt" ]; then
	echo "Unable to read a CA certificate from secret certificate-authority-tls in ocne-system"
	exit 1
fi

local_ui_port=10443
kubectl port-forward -n ocne-system "service/${ui_service}" "${local_ui_port}:${ui_service_port}" > "${tmpdir}/port-forward.log" 2>&1 &
port_forward_pid=$!

for _ in $(seq 1 24); do
	if grep -q "Forwarding from" "${tmpdir}/port-forward.log" 2>/dev/null; then
		break
	fi

	if ! kill -0 "$port_forward_pid" 2>/dev/null; then
		cat "${tmpdir}/port-forward.log"
		echo "kubectl port-forward to the UI service exited unexpectedly"
		exit 1
	fi

	sleep 1
done

if ! grep -q "Forwarding from" "${tmpdir}/port-forward.log" 2>/dev/null; then
	cat "${tmpdir}/port-forward.log"
	echo "Timed out waiting for kubectl port-forward to the UI service"
	exit 1
fi

for _ in $(seq 1 10); do
	openssl s_client -showcerts -connect "127.0.0.1:${local_ui_port}" -servername "${ui_service}.ocne-system.svc" </dev/null 2>/dev/null |
		awk 'BEGIN { capture = 0 } /BEGIN CERTIFICATE/ { capture = 1 } capture { print } /END CERTIFICATE/ { exit }' > "${tmpdir}/presented.crt"

	if [ -s "${tmpdir}/presented.crt" ]; then
		break
	fi

	sleep 1
done

if [ ! -s "${tmpdir}/presented.crt" ]; then
	echo "Unable to read a certificate from the UI service in ocne-system"
	exit 1
fi

secret_fingerprint=$(openssl x509 -in "${tmpdir}/ui-secret.crt" -noout -fingerprint -sha256)
presented_fingerprint=$(openssl x509 -in "${tmpdir}/presented.crt" -noout -fingerprint -sha256)

if [ "$secret_fingerprint" != "$presented_fingerprint" ]; then
	echo "The UI service certificate does not match the certificate stored in secret ui-tls"
	exit 1
fi

openssl verify -CAfile "${tmpdir}/ui-ca.crt" "${tmpdir}/presented.crt"
test_started=false

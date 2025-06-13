

%if 0%{?with_debug}
%global _dwz_low_mem_die_limit 0
%else
%global debug_package   %{nil}
%endif

%{!?registry: %global registry container-registry.oracle.com/olcne}
%global app_name               headlamp
%global img_name               ui
%global app_version            0.31.1
%global oracle_release_version 1
%global _buildhost             build-ol%{?oraclelinux}-%{?_arch}.oracle.com

Name:           %{app_name}-container-image
Version:        %{app_version}
Release:        %{oracle_release_version}%{?dist}
Summary:        Headlamp is an easy-to-use and extensible Kubernetes web UI
License:        Apache-2.0
Group:          System/Management
Url:            https://github.com/headlamp-k8s/headlamp.git
Source:         %{name}-%{version}.tar.bz2


%description
Headlamp is an easy-to-use and extensible Kubernetes web UI.

%prep
%setup -q -n %{name}-%{version}

%build
%global rpm_name %{app_name}-%{version}-%{release}.%{_build_arch}
%global docker_tag %{registry}/%{img_name}:v%{version}-ma

yum clean all
yumdownloader --destdir=${PWD}/rpms %{rpm_name}

podman build --squash --pull=never\
    --build-arg https_proxy=${https_proxy} \
    -t %{docker_tag} -f ./olm/builds/Dockerfile .
podman save -o %{img_name}.tar %{docker_tag}

%install
%__install -D -m 644 %{img_name}.tar %{buildroot}/usr/local/share/olcne/%{img_name}.tar

%files
%license LICENSE THIRD_PARTY_LICENSES.txt olm/SECURITY.md
/usr/local/share/olcne/%{img_name}.tar

%changelog
* Fri Mar 28 2025 Olcne-Builder Jenkins <olcne-builder_us@oracle.com> - 0.31.1-1
- Added Oracle specific build files for Headlamp.



%if 0%{?with_debug}
%global _dwz_low_mem_die_limit 0
%else
%global debug_package %{nil}
%endif

%global app_name                headlamp
%global app_version             0.31.1
%global oracle_release_version  1
%global _buildhost              build-ol%{?oraclelinux}-%{?_arch}.oracle.com

Name:           %{app_name}
Version:        %{app_version}
Release:        %{oracle_release_version}%{?dist}
Summary:        Headlamp is an easy-to-use and extensible Kubernetes web UI
License:        Apache-2.0
Group:          System/Management
Url:            https://github.com/headlamp-k8s/headlamp.git
Source:         %{name}-%{version}.tar.bz2
BuildRequires:  golang
BuildRequires:	nodejs >= 18.14
BuildRequires:	make
Patch0:         AppLogo.tsx.patch
Patch1:         themes.ts.patch

%description
Headlamp is an easy-to-use and extensible Kubernetes web UI.

%prep
%setup -q -n %{name}-%{version}
%patch0
%patch1

%build
cp olm/resources/*.svg frontend/src/resources
cp olm/icons/favicon.ico frontend/public/favicon.ico
cp olm/icons/favicon-16x16.png frontend/public/favicon-16x16.png
cp olm/icons/favicon-32x32.png frontend/public/favicon-32x32.png
cp olm/icons/favicon.ico frontend/public/icons.ico
cd backend
go mod tidy
cd ..
make backend frontend

%install
install -m 755 -d %{buildroot}/%{app_name}/frontend
cp -ap frontend/build/* %{buildroot}/%{app_name}/frontend
install -m 755 -d %{buildroot}/%{app_name}/backend
cp -ap backend/headlamp-server %{buildroot}/%{app_name}/backend

%files
%license LICENSE THIRD_PARTY_LICENSES.txt olm/SECURITY.md
/%{app_name}/

%changelog
* Fri Mar 28 2025 Olcne-Builder Jenkins <olcne-builder_us@oracle.com> - 0.31.1-1
- Added Oracle specific build files for Headlamp.

# Quick Send RPM spec. Packages a prebuilt Flutter Linux release bundle.
# Build input: quicksend-%{version}-linux-x86_64.tar.gz created by
# packaging/rpm/build-rpm.sh from app/build/linux/x64/release/bundle plus
# desktop/metainfo/icon/firewalld files.

%global debug_package %{nil}
%global __provides_exclude_from ^/opt/quicksend/.*$
%global __requires_exclude ^(libflutter_linux_gtk|libapp|librust_lib_localsend_app|libdartjni|lib.*_plugin|libjvm)\\.so.*$

Name:           quicksend
Version:        %{?qs_version}%{!?qs_version:0.1.0}
Release:        1%{?dist}
Summary:        Share files securely over your local network
License:        Apache-2.0
Source0:        quicksend-%{version}-linux-x86_64.tar.gz
ExclusiveArch:  x86_64

Requires:       gtk3
Requires:       xdg-user-dirs
Requires:       xdg-desktop-portal
Requires:       (xdg-desktop-portal-gtk or xdg-desktop-portal-gnome or xdg-desktop-portal-kde)
Requires:       mesa-libEGL
Requires:       mesa-libGLES
Recommends:     firewalld-filesystem
BuildRequires:  desktop-file-utils
BuildRequires:  patchelf

%description
Quick Send transfers files between devices on the same local network over
HTTPS with automatically generated TLS certificates. It is based on LocalSend
(Apache-2.0) and stays protocol-compatible with LocalSend clients.

%prep
%setup -q -n quicksend-%{version}

%install
mkdir -p %{buildroot}/opt/quicksend %{buildroot}%{_bindir}
cp -a bundle/. %{buildroot}/opt/quicksend/
# Flutter builds leave absolute build-tree RUNPATHs; keep only $ORIGIN.
for so in %{buildroot}/opt/quicksend/lib/*.so; do patchelf --set-rpath '$ORIGIN' "$so"; done
patchelf --set-rpath '$ORIGIN/lib' %{buildroot}/opt/quicksend/quicksend
ln -s /opt/quicksend/quicksend %{buildroot}%{_bindir}/quicksend
install -Dm644 com.ensignsoft.quicksend.desktop %{buildroot}%{_datadir}/applications/com.ensignsoft.quicksend.desktop
install -Dm644 com.ensignsoft.quicksend.metainfo.xml %{buildroot}%{_metainfodir}/com.ensignsoft.quicksend.metainfo.xml
mkdir -p %{buildroot}%{_datadir}/icons
cp -a icons/hicolor %{buildroot}%{_datadir}/icons/
install -Dm644 quicksend.xml %{buildroot}%{_prefix}/lib/firewalld/services/quicksend.xml
install -Dm644 LICENSE %{buildroot}%{_datadir}/licenses/%{name}/LICENSE
install -Dm644 NOTICE %{buildroot}%{_datadir}/licenses/%{name}/NOTICE

%check
desktop-file-validate %{buildroot}%{_datadir}/applications/com.ensignsoft.quicksend.desktop

%post
if [ -x /usr/bin/firewall-cmd ] && /usr/bin/firewall-cmd --state >/dev/null 2>&1; then
  /usr/bin/firewall-cmd --reload >/dev/null 2>&1 || :
fi

%postun
if [ -x /usr/bin/firewall-cmd ] && /usr/bin/firewall-cmd --state >/dev/null 2>&1; then
  /usr/bin/firewall-cmd --reload >/dev/null 2>&1 || :
fi

%files
%license %{_datadir}/licenses/%{name}/LICENSE
%license %{_datadir}/licenses/%{name}/NOTICE
/opt/quicksend
%{_bindir}/quicksend
%{_datadir}/applications/com.ensignsoft.quicksend.desktop
%{_metainfodir}/com.ensignsoft.quicksend.metainfo.xml
%{_datadir}/icons/hicolor/*/apps/com.ensignsoft.quicksend*.png
%{_prefix}/lib/firewalld/services/quicksend.xml

%changelog
* Sun Nov 08 2026 Muhammed Alparslan Sancaktar <codealpx@gmail.com> - 0.1.0-1
- Initial Quick Send package

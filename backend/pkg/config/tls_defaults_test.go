//nolint:testpackage // Tests the unexported TLS defaulting helper with an injected file check.
package config

import "testing"

func TestSetInClusterTLSDefaultsUsesLegacyPathsWhenBothFilesAreMounted(t *testing.T) {
	conf := Config{InCluster: true}
	existingPath := map[string]bool{
		defaultInClusterTLSCertPath: true,
		defaultInClusterTLSKeyPath:  true,
	}

	assertInClusterTLSDefaults(t, conf, existingPath, defaultInClusterTLSCertPath, defaultInClusterTLSKeyPath)
}

func TestSetInClusterTLSDefaultsKeepsEmptyPathsWhenLegacyFilesAreNotMounted(t *testing.T) {
	conf := Config{InCluster: true}

	assertInClusterTLSDefaults(t, conf, map[string]bool{}, "", "")
}

func TestSetInClusterTLSDefaultsSkipsNonInClusterMode(t *testing.T) {
	conf := Config{}
	existingPath := map[string]bool{
		defaultInClusterTLSCertPath: true,
		defaultInClusterTLSKeyPath:  true,
	}

	assertInClusterTLSDefaults(t, conf, existingPath, "", "")
}

func TestSetInClusterTLSDefaultsPreservesExplicitTLSPaths(t *testing.T) {
	conf := Config{
		InCluster:   true,
		TLSCertPath: "/custom/tls.crt",
		TLSKeyPath:  "/custom/tls.key",
	}
	existingPath := map[string]bool{
		defaultInClusterTLSCertPath: true,
		defaultInClusterTLSKeyPath:  true,
	}

	assertInClusterTLSDefaults(t, conf, existingPath, "/custom/tls.crt", "/custom/tls.key")
}

func assertInClusterTLSDefaults(
	t *testing.T,
	conf Config,
	existingPath map[string]bool,
	wantCertPath string,
	wantKeyPath string,
) {
	t.Helper()

	setInClusterTLSDefaultsWithFileCheck(&conf, func(path string) bool {
		return existingPath[path]
	})

	if conf.TLSCertPath != wantCertPath {
		t.Fatalf("TLSCertPath = %q, want %q", conf.TLSCertPath, wantCertPath)
	}

	if conf.TLSKeyPath != wantKeyPath {
		t.Fatalf("TLSKeyPath = %q, want %q", conf.TLSKeyPath, wantKeyPath)
	}
}

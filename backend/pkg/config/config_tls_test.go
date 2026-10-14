package config //nolint:testpackage // Verify unexported TLS fallback without creating system paths.

import "testing"

func TestSetInClusterTLSDefaults(t *testing.T) {
	tests := []struct {
		name     string
		config   Config
		files    map[string]bool
		wantCert string
		wantKey  string
	}{
		{"mounted_pair", Config{InCluster: true}, map[string]bool{
			defaultInClusterTLSCertPath: true, defaultInClusterTLSKeyPath: true,
		}, defaultInClusterTLSCertPath, defaultInClusterTLSKeyPath},
		{"missing_cert", Config{InCluster: true}, map[string]bool{
			defaultInClusterTLSKeyPath: true,
		}, "", ""},
		{"missing_key", Config{InCluster: true}, map[string]bool{
			defaultInClusterTLSCertPath: true,
		}, "", ""},
		{"outside_cluster", Config{}, nil, "", ""},
		{"explicit_cert", Config{InCluster: true, TLSCertPath: "/custom/cert"}, nil, "/custom/cert", ""},
		{"explicit_key", Config{InCluster: true, TLSKeyPath: "/custom/key"}, nil, "", "/custom/key"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			setInClusterTLSDefaultsWithFileCheck(&tt.config, func(path string) bool { return tt.files[path] })

			if tt.config.TLSCertPath != tt.wantCert || tt.config.TLSKeyPath != tt.wantKey {
				t.Errorf("TLS paths = (%q, %q), want (%q, %q)",
					tt.config.TLSCertPath, tt.config.TLSKeyPath, tt.wantCert, tt.wantKey)
			}
		})
	}
}

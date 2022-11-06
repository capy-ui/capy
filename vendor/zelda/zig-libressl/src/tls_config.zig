const std = @import("std");
const root = @import("main.zig");
const tls = root.tls;

pub const TlsConfigurationParams = struct {
    const Self = @This();
    pub const Protocol = enum {
        tls1_0,
        tls1_1,
        tls1_2,
        tls1_3,
        tls1,
        all,
        default,

        fn native(self: Protocol) u32 {
            return switch (self) {
                .tls1_0 => tls.TLS_PROTOCOL_TLSv1_0,
                .tls1_1 => tls.TLS_PROTOCOL_TLSv1_1,
                .tls1_2 => tls.TLS_PROTOCOL_TLSv1_2,
                .tls1_3 => tls.TLS_PROTOCOL_TLSv1_3,
                .tls1 => tls.TLS_PROTOCOL_TLSv1,
                .all => tls.TLS_PROTOCOLS_ALL,
                .default => tls.TLS_PROTOCOLS_DEFAULT,
            };
        }
    };

    // NOTE(haze): we don't use `@tagName` here because enum tags are interned and don't come with a
    // null byte (which is what libtls needs)

    pub const Ciphers = union(enum) {
        secure,
        compat,
        legacy,
        insecure,
        custom: [*:0]const u8,

        pub fn native(self: Ciphers) [*:0]const u8 {
            return switch (self) {
                .custom => |payload| payload,
                else => @tagName(self)
            };
        }
    };

    pub const DheParams = enum {
        none,
        auto,
        legacy,

        pub fn native(self: DheParams) []const u8 {
            return switch (self) {
                .none => "none",
                .auto => "auto",
                .legacy => "legacy",
            };
        }
    };

    const RootCertificateLoadingMechanism = union(enum) {
        /// sets the path (directory) which should be searched for root certificates.
        dir_path: []const u8,
        /// loads a file containing the root certificates.
        file_path: []const u8,
        /// sets the root certificates directly from memory.
        memory: []const u8,
        /// load the default ca_cert as reported by `tls_default_ca_cert_file`
        default: void,
    };

    const LoadingMechanism = union(enum) {
        /// loads a file containing the item.
        file_path: []const u8,
        /// sets the item directly from memory.
        memory: []const u8,
    };

    const KeypairLoadingMechanism = union(enum) {
        /// loads two files from which the public certificate and private key will be read.
        file_path: struct {
            cert_file_path: []const u8,
            key_file_path: []const u8,
        },
        /// directly sets the public certificate and private key from memory.
        memory: struct {
            cert_memory: []const u8,
            key_memory: []const u8,
        },
    };

    const KeypairOcspLoadingMechanism = union(enum) {
        /// loads three files containing the public certificate, private key, and DER-encoded OCSP staple.
        file_path: struct {
            cert_file_path: []const u8,
            key_file_path: []const u8,
            ocsp_file_path: []const u8,
        },
        /// directly sets the public certificate, private key, and DER-encoded OCSP staple from memory.
        memory: struct {
            cert_memory: []const u8,
            key_memory: []const u8,
            ocsp_memory: []const u8,
        },
    };

    /// specifies which versions of the TLS protocol may be used.
    protocol: Protocol = .default,

    /// sets the ALPN protocols that are supported. The alpn string is a comma separated list of protocols, in order of preference.
    alpn_protocols: ?[]const u8 = null,

    /// sets the list of ciphers that may be used.
    ciphers: Ciphers = .secure,

    /// specifies the parameters that will be used during Diffie-Hellman Ephemeral (DHE) key exchange
    /// In auto mode, the key size for the ephemeral key is automatically selected based on the size of the private key being used for signing. In legacy mode, 1024 bit ephemeral keys are used. The default value is none, which disables DHE key exchange.
    dhe_params: DheParams = .none,

    /// specifies the names of the elliptic curves that may be used during Elliptic Curve Diffie-Hellman Ephemeral (ECDHE) key exchange. This is a comma separated list, given in order of preference. The special value of "default" will use the default curves (currently X25519, P-256 and P-384).
    ecdhe_curves: []const u8 = "default",

    /// prefers ciphers in the client's cipher list when selecting a cipher suite (server only). This is considered to be less secure than preferring the server's list.
    prefer_client_ciphers: bool = false,

    /// prefers ciphers in the server's cipher list when selecting a cipher suite (server only). This is considered to be more secure than preferring the client's list and is the default.
    prefer_server_ciphers: bool = true,

    /// requires that a valid stapled OCSP response be provided during the TLS handshake.
    require_oscp_stapling: bool = false,

    ca: ?RootCertificateLoadingMechanism = null,

    cert: ?LoadingMechanism = null,
    crl: ?LoadingMechanism = null,
    key: ?LoadingMechanism = null,
    ocsp_staple: ?LoadingMechanism = null,
    keypair: ?KeypairLoadingMechanism = null,
    keypair_ocsp: ?KeypairOcspLoadingMechanism = null,

    /// limits the number of intermediate certificates that will be followed during certificate validation.
    verify_depth: ?usize = null,

    /// enables client certificate verification, requiring the client to send a certificate (server only).
    verify_client: bool = false,

    /// enables client certificate verification, without requiring the client to send a certificate (server only).
    verify_client_optional_cert: bool = false,

    const BuildError = error{
        OutOfMemory,
        BadProtocols,
        BadAlpn,
        BadCiphers,
        BadDheParams,
        BadEcdheCurves,
        BadVerifyDepth,

        BadCaPath,
        BadCaFilePath,
        BadCaMemory,
        BadDefaultCaCertFile,

        BadCertFilePath,
        BadCertMemory,

        BadCrlFilePath,
        BadCrlMemory,

        BadKeyFilePath,
        BadKeyMemory,

        BadOcspStapleFilePath,
        BadOcspStapleMemory,

        BadKeypairFilePath,
        BadKeypairMemory,

        BadKeypairOcspFilePath,
        BadKeypairOcspMemory,
    };

    pub fn build(self: Self) BuildError!TlsConfiguration {
        const maybe_config = tls.tls_config_new();
        if (maybe_config == null) return error.OutOfMemory;
        var config = maybe_config.?;

        if (tls.tls_config_set_protocols(config, self.protocol.native()) == -1)
            return error.BadProtocols;

        if (self.alpn_protocols) |alpn_protocols|
            if (tls.tls_config_set_alpn(config, alpn_protocols.ptr) == -1)
                return error.BadAlpn;

        if (tls.tls_config_set_ciphers(config, self.ciphers.native()) == -1)
            return error.BadCiphers;
        if (tls.tls_config_set_dheparams(config, self.dhe_params.native().ptr) == -1)
            return error.BadDheParams;
        if (tls.tls_config_set_ecdhecurves(config, self.ecdhe_curves.ptr) == -1)
            return error.BadEcdheCurves;

        if (self.prefer_server_ciphers)
            tls.tls_config_prefer_ciphers_server(config);

        if (self.prefer_client_ciphers)
            tls.tls_config_prefer_ciphers_client(config);

        if (self.require_oscp_stapling)
            tls.tls_config_ocsp_require_stapling(config);

        if (self.verify_depth) |depth|
            if (tls.tls_config_set_verify_depth(config, @intCast(c_int, depth)) == -1)
                return error.BadVerifyDepth;

        if (self.verify_client)
            tls.tls_config_verify_client(config);

        if (self.verify_client_optional_cert)
            tls.tls_config_verify_client_optional(config);

        if (self.ca) |ca_mechanism| {
            switch (ca_mechanism) {
                .dir_path => |path| if (tls.tls_config_set_ca_path(config, path.ptr) == -1) return error.BadCaPath,
                .file_path => |path| if (tls.tls_config_set_ca_file(config, path.ptr) == -1) return error.BadCaFilePath,
                .memory => |data| if (tls.tls_config_set_ca_mem(config, data.ptr, data.len) == -1) return error.BadCaMemory,
                .default => if (tls.tls_config_set_ca_file(config, tls.tls_default_ca_cert_file()) == -1) return error.BadDefaultCaCertFile,
            }
        }

        if (self.cert) |cert_loading_mechanism| {
            switch (cert_loading_mechanism) {
                .file_path => |path| if (tls.tls_config_set_cert_file(config, path.ptr) == -1) return error.BadCertFilePath,
                .memory => |data| if (tls.tls_config_set_cert_mem(config, data.ptr, data.len) == -1) return error.BadCertMemory,
            }
        }

        if (self.crl) |crl_loading_mechanism| {
            switch (crl_loading_mechanism) {
                .file_path => |path| if (tls.tls_config_set_crl_file(config, path.ptr) == -1) return error.BadCrlFilePath,
                .memory => |data| if (tls.tls_config_set_crl_mem(config, data.ptr, data.len) == -1) return error.BadCrlMemory,
            }
        }

        if (self.key) |key_loading_mechanism| {
            switch (key_loading_mechanism) {
                .file_path => |path| if (tls.tls_config_set_key_file(config, path.ptr) == -1) return error.BadKeyFilePath,
                .memory => |data| if (tls.tls_config_set_key_mem(config, data.ptr, data.len) == -1) return error.BadKeyMemory,
            }
        }

        if (self.ocsp_staple) |ocsp_staple_loading_mechanism| {
            switch (ocsp_staple_loading_mechanism) {
                .file_path => |path| if (tls.tls_config_set_ocsp_staple_file(config, path.ptr) == -1) return error.BadOcspStapleFilePath,
                .memory => |data| if (tls.tls_config_set_ocsp_staple_mem(config, data.ptr, data.len) == -1) return error.BadOcspStapleMemory,
            }
        }

        if (self.keypair) |keypair_loading_mechanism| {
            switch (keypair_loading_mechanism) {
                .file_path => |paths| if (tls.tls_config_set_keypair_file(config, paths.cert_file_path.ptr, paths.key_file_path.ptr) == -1) return error.BadKeypairFilePath,
                .memory => |data| if (tls.tls_config_set_keypair_mem(config, data.cert_memory.ptr, data.cert_memory.len, data.key_memory.ptr, data.key_memory.len) == -1) return error.BadKeypairMemory,
            }
        }

        if (self.keypair_ocsp) |keypair_ocsp_loading_mechanism| {
            switch (keypair_ocsp_loading_mechanism) {
                .file_path => |paths| if (tls.tls_config_set_keypair_ocsp_file(config, paths.cert_file_path.ptr, paths.key_file_path.ptr, paths.ocsp_file_path.ptr) == -1) return error.BadKeypairOcspFilePath,
                .memory => |data| if (tls.tls_config_set_keypair_ocsp_mem(config, data.cert_memory.ptr, data.cert_memory.len, data.key_memory.ptr, data.key_memory.len, data.ocsp_memory.ptr, data.ocsp_memory.len) == -1) return error.BadKeypairOcspMemory,
            }
        }

        return TlsConfiguration{
            .params = self,
            .config = config,
        };
    }
};

pub const TlsConfiguration = struct {
    const Self = @This();

    params: TlsConfigurationParams,
    config: *tls.tls_config,

    pub fn deinit(self: *Self) void {
        tls.tls_config_free(self.config);
        self.* = undefined;
    }
};

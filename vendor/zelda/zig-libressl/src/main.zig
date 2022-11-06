const std = @import("std");
pub const out = std.log.scoped(.libressl);

pub const tls = @cImport({
    @cInclude("tls.h");
});

const tls_config = @import("tls_config.zig");
pub const TlsConfiguration = tls_config.TlsConfiguration;
pub const TlsConfigurationParams = tls_config.TlsConfigurationParams;
pub const SslStream = @import("SslStream.zig");
pub const SslServer = @import("SslServer.zig");

pub fn closeTlsContext(tls_context: *tls.tls, handle: std.os.socket_t) !void {
    const was_close_successful = blk: {
        var initial_close_attempt_value = tls.tls_close(tls_context);
        if (std.io.is_async) {
            while (initial_close_attempt_value == tls.TLS_WANT_POLLIN or initial_close_attempt_value == tls.TLS_WANT_POLLIN) {
                if (initial_close_attempt_value == tls.TLS_WANT_POLLIN) {
                    std.event.Loop.instance.?.waitUntilFdReadable(handle);
                } else {
                    std.event.Loop.instance.?.waitUntilFdWritable(handle);
                }
                initial_close_attempt_value = tls.tls_close(tls_context);
            }
        }
        break :blk initial_close_attempt_value == 0;
    };
    if (!was_close_successful)
        return error.TlsClose;
}

// TODO(haze): reuse tls session file https://man.openbsd.org/tls_config_set_session_id.3
// TODO(haze): tls noverify https://man.openbsd.org/tls_config_verify.3
// TODO(haze): investigate tls_client/tls_server NULL return as OOM
// TODO(haze): tls_context reporting (tls version, issuer, expiry, etc)

// TODO(haze): better error parsing
// TODO(haze): tls keypair/oscp add
// TODO(haze): debug annotations

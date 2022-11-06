const std = @import("std");

pub const log = std.log.scoped(.hzzp);

pub const supported_versions = std.builtin.Version.Range{
    .min = .{
        .major = 1,
        .minor = 0,
    },
    .max = .{
        .major = 1,
        .minor = 1,
    },
};

// zig fmt: off
pub const StatusCode = enum(u10) {
    // https://www.iana.org/assignments/http-status-codes/http-status-codes.txt (2018-09-21)

    info_continue = 100,                           // RFC7231, Section 6.2.1
    info_switching_protocols = 101,                // RFC7231, Section 6.2.2
    info_processing = 102,                         // RFC2518
    info_early_hints = 103,                        // RFC8297
    // 104-199 Unassigned

    success_ok = 200,                              // RFC7231, Section 6.3.1
    success_created = 201,                         // RFC7231, Section 6.3.2
    success_accepted = 202,                        // RFC7231, Section 6.3.3
    success_non_authoritative_information = 203,   // RFC7231, Section 6.3.4
    success_no_content = 204,                      // RFC7231, Section 6.3.5
    success_reset_content = 205,                   // RFC7231, Section 6.3.6
    success_partial_content = 206,                 // RFC7233, Section 4.1
    success_multi_status = 207,                    // RFC4918
    success_already_reported = 208,                // RFC5842
    // 209-225 Unassigned
    success_im_used = 226,                         // RFC3229
    // 227-299 Unassigned

    redirect_multiple_choices = 300,               // RFC7231, Section 6.4.1
    redirect_moved_permanently = 301,              // RFC7231, Section 6.4.2
    redirect_found = 302,                          // RFC7231, Section 6.4.3
    redirect_see_other = 303,                      // RFC7231, Section 6.4.4
    redirect_not_modified = 304,                   // RFC7232, Section 4.1
    redirect_use_proxy = 305,                      // RFC7231, Section 6.4.5
    // 306 (Unused)
    redirect_temporary_redirect = 307,             // RFC7231, Section 6.4.7
    redirect_permanent_redirect = 308,             // RFC7538
    // 309-399 Unassigned

    client_bad_request = 400,                      // RFC7231, Section 6.5.1
    client_unauthorized = 401,                     // RFC7235, Section 3.1
    client_payment_required = 402,                 // RFC7231, Section 6.5.2
    client_forbidden = 403,                        // RFC7231, Section 6.5.3
    client_not_found = 404,                        // RFC7231, Section 6.5.4
    client_method_not_allowed = 405,               // RFC7231, Section 6.5.5
    client_not_acceptable = 406,                   // RFC7231, Section 6.5.6
    client_proxy_authentication_required = 407,    // RFC7235, Section 3.2
    client_request_timeout = 408,                  // RFC7231, Section 6.5.7
    client_conflict = 409,                         // RFC7231, Section 6.5.8
    client_gone = 410,                             // RFC7231, Section 6.5.9
    client_length_required = 411,                  // RFC7231, Section 6.5.10
    client_precondition_failed = 412,              // RFC7232, Section 4.2][RFC8144, Section 3.2
    client_payload_too_large = 413,                // RFC7231, Section 6.5.11
    client_uri_too_long = 414,                     // RFC7231, Section 6.5.12
    client_unsupported_media_type = 415,           // RFC7231, Section 6.5.13][RFC7694, Section 3
    client_range_not_satisfiable = 416,            // RFC7233, Section 4.4
    client_expectation_failed = 417,               // RFC7231, Section 6.5.14
    // 418-420 Unassigned
    client_misdirected_request = 421,              // RFC7540, Section 9.1.2
    client_unprocessable_entity = 422,             // RFC4918
    client_locked = 423,                           // RFC4918
    client_failed_dependency = 424,                // RFC4918
    client_too_early = 425,                        // RFC8470
    client_upgrade_required = 426,                 // RFC7231, Section 6.5.15
    // 427 Unassigned
    client_precondition_required = 428,            // RFC6585
    client_too_many_requests = 429,                // RFC6585
    // 430 Unassigned
    client_request_header_fields_too_large = 431,  // RFC6585
    // 432-450 Unassigned
    client_unavailable_for_legal_reasons = 451,    // RFC7725
    // 452-499 Unassigned

    server_internal_server_error = 500,            // RFC7231, Section 6.6.1
    server_not_implemented = 501,                  // RFC7231, Section 6.6.2
    server_bad_gateway = 502,                      // RFC7231, Section 6.6.3
    server_service_unavailable = 503,              // RFC7231, Section 6.6.4
    server_gateway_timeout = 504,                  // RFC7231, Section 6.6.5
    server_http_version_not_supported = 505,       // RFC7231, Section 6.6.6
    server_variant_also_negotiates = 506,          // RFC2295
    server_insufficient_storage = 507,             // RFC4918
    server_loop_detected = 508,                    // RFC5842
    // 509 Unassigned
    server_not_extended = 510,                     // RFC2774
    server_network_authentication_required = 511,  // RFC6585
    // 512-599 Unassigned

    _,

    pub fn code(self: StatusCode) std.meta.Tag(StatusCode) {
        return @enumToInt(self);
    }

    pub fn isValid(self: StatusCode) bool {
        return @enumToInt(self) >= 100 and @enumToInt(self) < 600;
    }

    pub const Group = enum { info, success, redirect, client_error, server_error, invalid };
    pub fn group(self: StatusCode) Group {
        return switch (self.code()) {
            100...199 => .info,
            200...299 => .success,
            300...399 => .redirect,
            400...499 => .client_error,
            500...599 => .server_error,
            else => .invalid,
        };
    }
};
// zig fmt: on

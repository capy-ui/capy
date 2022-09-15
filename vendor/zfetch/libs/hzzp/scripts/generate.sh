#!/bin/sh

curl -so status_codes.csv "https://www.iana.org/assignments/http-status-codes/http-status-codes-1.csv"
zig run generate_status_codes.zig
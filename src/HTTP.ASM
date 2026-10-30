; HTTP.ASM -- restricted HTTP/1.1 POST /msxchat/v1/exchange.
; Bounded header lines and Content-Length, close-delimited transaction.
http_request_header:
    ld de,NETTX
    ld hl,http_post
    call http_append
    ld hl,net_host
    call http_append
    ld hl,http_fields
    call http_append
    ; Unsigned decimal Content-Length, no leading zero.
    ld hl,(net_request_length)
    ld (http_number),hl
    xor a
    ld (http_printed),a
    ld ix,http_divisors
    ld b,5
http_decimal_loop:
    push bc
    ld e,(ix+0)
    ld d,(ix+1)
    ld hl,(http_number)
    ld c,0
http_decimal_sub:
    or a
    sbc hl,de
    jp c,http_decimal_end
    inc c
    jp http_decimal_sub
http_decimal_end:
    add hl,de
    ld (http_number),hl
    ld a,c
    or a
    jp nz,http_decimal_emit
    ld a,(http_printed)
    or a
    jp nz,http_decimal_emit
    ld a,(ix+0)
    cp 1
    jp nz,http_decimal_next
http_decimal_emit:
    ld a,1
    ld (http_printed),a
    ld hl,(http_output_pointer)
    ld a,c
    add a,48
    ld (hl),a
    inc hl
    ld (http_output_pointer),hl
http_decimal_next:
    inc ix
    inc ix
    pop bc
    djnz http_decimal_loop
    ld de,(http_output_pointer)
    ld hl,http_tail
    call http_append
    ld hl,(http_output_pointer)
    ld de,NETTX
    or a
    sbc hl,de
    ld (net_tx_count),hl
    jp net_send
; HL NUL string, DE next output position. Total built header <256 by bounds.
http_append:
    ld a,(hl)
    or a
    jp z,http_append_done
    ld (de),a
    inc hl
    inc de
    jp http_append
http_append_done:
    ld (http_output_pointer),de
    ret

http_receive_headers:
    xor a
    ld (http_seen_length),a
    ld (http_seen_type),a
    ld hl,0
    ld (http_header_bytes),hl
    call http_line
    ret c
    ld hl,NETLINE
    ld de,http_version
    call http_prefix
    jp nz,net_http_fail_return
    ld a,(hl)
    cp 48
    jp z,http_status_version
    cp 49
    jp nz,net_http_fail_return
http_status_version:
    inc hl
    ld (http_status_pointer),hl
    ld de,http_ok
    call http_prefix
    jp z,http_status_ok
    ld hl,(http_status_pointer)
    ld de,http_accepted
    call http_prefix
    jp nz,net_http_fail_return
    ld a,(hl)
    or a
    jp z,http_processing
    cp 32
    jp nz,net_http_fail_return
http_processing:
    ld a,9
    jp net_error_return
http_status_ok:
    ld a,(hl)
    or a
    jp z,http_header_loop
    cp 32
    jp nz,net_http_fail_return
http_header_loop:
    call http_line
    ret c
    ld a,(NETLINE)
    or a
    jp z,http_headers_end
    ld hl,NETLINE
    ld de,http_cl
    call http_prefix
    jp z,http_content_length
    ld hl,NETLINE
    ld de,http_te
    call http_prefix
    jp z,net_http_fail_return
    ld hl,NETLINE
    ld de,http_ce
    call http_prefix
    jp z,net_http_fail_return
    ld hl,NETLINE
    ld de,http_ct
    call http_prefix
    jp z,http_content_type
    ; Unknown fields must have a nonempty name without SP/HTAB, and a colon.
    ld a,(NETLINE)
    cp 58
    jp z,net_http_fail_return
    ld hl,NETLINE
http_unknown_name:
    ld a,(hl)
    cp 33
    jp c,net_http_fail_return
    cp 58
    jp z,http_header_loop
    inc hl
    jp http_unknown_name
http_content_length:
    ld a,(http_seen_length)
    or a
    jp nz,net_http_fail_return
    inc a
    ld (http_seen_length),a
    call net_skip_ows
    call net_uint16
    jp c,net_http_fail_return
    bit 7,d
    jp nz,net_http_fail_return
    ld a,d
    or e
    jp z,net_http_fail_return
    ld (http_length),de
    call net_skip_ows
    ld a,(hl)
    or a
    jp nz,net_http_fail_return
    jp http_header_loop
http_content_type:
    ld a,(http_seen_type)
    or a
    jp nz,net_http_fail_return
    inc a
    ld (http_seen_type),a
    call net_skip_ows
    ld de,http_json
    call http_prefix
    jp nz,net_http_fail_return
    call net_skip_ows
    ld a,(hl)
    or a
    jp z,http_header_loop
    cp 59
    jp nz,net_http_fail_return
    jp http_header_loop
http_headers_end:
    ld a,(http_seen_length)
    ld b,a
    ld a,(http_seen_type)
    and b
    jp z,net_http_fail_return
    or a
    ret
; ASCII-insensitive literal prefix. Z on success; HL after prefix.
http_prefix:
    ld a,(de)
    or a
    ret z
    ld c,a
    ld a,(hl)
    cp 65
    jp c,http_prefix_folded
    cp 91
    jp nc,http_prefix_folded
    add a,32
http_prefix_folded:
    cp c
    ret nz
    inc hl
    inc de
    jp http_prefix

http_line:
    ld hl,NETLINE
    ld (http_line_pointer),hl
    xor a
    ld (http_line_length),a
http_line_loop:
    call net_receive_byte
    ret c
    ld (http_line_char),a
    call http_count_header
    ret c
    ld a,(http_line_char)
    cp 13
    jp z,http_line_cr
    cp 9
    jp z,http_line_store
    cp 32
    jp c,net_http_fail_return
    cp 127
    jp nc,net_http_fail_return
http_line_store:
    ld hl,(http_line_pointer)
    ld (hl),a
    inc hl
    ld (http_line_pointer),hl
    ld a,(http_line_length)
    inc a
    ld (http_line_length),a
    jp z,net_http_fail_return
    jp http_line_loop
http_line_cr:
    call net_receive_byte
    ret c
    cp 10
    jp nz,net_http_fail_return
    call http_count_header
    ret c
    ld hl,(http_line_pointer)
    xor a
    ld (hl),a
    ret
http_count_header:
    ld hl,(http_header_bytes)
    inc hl
    ld (http_header_bytes),hl
    ld de,2049
    or a
    sbc hl,de
    jp nc,net_http_fail_return
    or a
    ret

http_length: dw 0
http_seen_length: db 0
http_seen_type: db 0
http_header_bytes: dw 0
http_line_pointer: dw 0
http_line_length: db 0
http_line_char: db 0
http_number: dw 0
http_printed: db 0
http_output_pointer: dw 0
http_divisors: dw 10000,1000,100,10,1
http_post: dm "POST /msxchat/v1/exchange HTTP/1.1"
    db 13,10
    dm "Host: "
    db 0
http_fields: db 13,10
    dm "Content-Type: application/json"
    db 13,10
    dm "Content-Length: "
    db 0
http_tail: db 13,10
    dm "Connection: close"
    db 13,10,13,10,0
http_version: dm "http/1."
    db 0
http_ok: dm " 200"
    db 0
http_cl: dm "content-length:"
    db 0
http_te: dm "transfer-encoding:"
    db 0
http_ce: dm "content-encoding:"
    db 0
http_ct: dm "content-type:"
    db 0
http_json: dm "application/json"
    db 0

http_status_pointer: dw 0
http_accepted: dm " 202"
    db 0

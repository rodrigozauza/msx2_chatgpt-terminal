; NETCONFIG.ASM -- numeric private IPv4 + port in DOS command tail.
net_configure:
    ld a,(&80)
    or a
    ret z
    call net_parse_args
    ld a,2
    jp c,net_config_store
    ld a,1
net_config_store:
    ld (net_config),a
    ret
net_show_config:
    ld a,(net_config)
    or a
    ret z
    cp 1
    ld hl,net_note_config_bad
    jp nz,storage_note
    xor a
    ld hl,net_title
    call put_line
    ld hl,net_note_config
    call storage_note
    ld hl,net_host
    jp storage_note

net_parse_args:
    ld a,(&80)
    cp 128
    jp nc,net_parse_fail
    ld c,a
    ld b,0
    ld hl,&81
    ld de,NETLINE
    ldir
    xor a
    ld (de),a
    ld hl,NETLINE
    call net_skip_ows
    ld (net_ip_start),hl
    ld a,4
    ld (net_octets),a
    ld de,net_params
    ld (net_octet_ptr),de
net_parse_octet:
    call net_uint16
    ret c
    ld a,d
    or a
    jp nz,net_parse_fail
    push hl
    ld hl,(net_octet_ptr)
    ld (hl),e
    inc hl
    ld (net_octet_ptr),hl
    pop hl
    ld a,(net_octets)
    dec a
    ld (net_octets),a
    jp z,net_parse_port
    ld a,(hl)
    cp 46
    jp nz,net_parse_fail
    inc hl
    jp net_parse_octet
net_parse_port:
    push hl
    ld de,(net_ip_start)
    or a
    sbc hl,de
    ld de,16
    or a
    sbc hl,de
    pop hl
    jp nc,net_parse_fail
    ld a,(hl)
    cp 32
    jp nz,net_parse_fail
    call net_skip_ows
    ld (net_port_start),hl
    call net_uint16
    ret c
    ld a,d
    or e
    jp z,net_parse_fail
    ld (net_params+4),de
    push hl
    ld de,(net_port_start)
    or a
    sbc hl,de
    ld de,6
    or a
    sbc hl,de
    pop hl
    jp nc,net_parse_fail
    call net_skip_ows
    ld a,(hl)
    or a
    jp nz,net_parse_fail
    ; RFC1918 targets only. No DNS or TLS is implied.
    ld a,(net_params)
    cp 10
    jp z,net_host_build
    cp 192
    jp nz,net_private_172
    ld a,(net_params+1)
    cp 168
    jp nz,net_parse_fail
    jp net_host_build
net_private_172:
    cp 172
    jp nz,net_parse_fail
    ld a,(net_params+1)
    sub 16
    cp 16
    jp nc,net_parse_fail
net_host_build:
    ld hl,(net_ip_start)
    ld de,net_host
net_host_ip:
    ld a,(hl)
    cp 32
    jp z,net_host_port
    ld (de),a
    inc hl
    inc de
    jp net_host_ip
net_host_port:
    ld a,58
    ld (de),a
    inc de
    ld hl,(net_port_start)
net_host_digits:
    ld a,(hl)
    cp 48
    jp c,net_host_done
    cp 58
    jp nc,net_host_done
    ld (de),a
    inc hl
    inc de
    jp net_host_digits
net_host_done:
    xor a
    ld (de),a
    ret
net_skip_ows:
    ld a,(hl)
    cp 32
    jp z,net_skip_one
    cp 9
    ret nz
net_skip_one:
    inc hl
    jp net_skip_ows
; HL text -> DE uint16, HL delimiter, carry on no digits/overflow.
net_uint16:
    ld de,0
    xor a
    ld (net_digits),a
net_uint_digit:
    ld a,(hl)
    cp 48
    jp c,net_uint_done
    cp 58
    jp nc,net_uint_done
    sub 48
    ld (net_digit),a
    ld a,1
    ld (net_digits),a
    push hl
    ld h,d
    ld l,e
    add hl,hl
    jp c,net_uint_overflow
    ld b,h
    ld c,l
    add hl,hl
    jp c,net_uint_overflow
    add hl,hl
    jp c,net_uint_overflow
    add hl,bc
    jp c,net_uint_overflow
    ld a,(net_digit)
    ld c,a
    ld b,0
    add hl,bc
    jp c,net_uint_overflow
    ex de,hl
    pop hl
    inc hl
    jp net_uint_digit
net_uint_overflow:
    pop hl
net_parse_fail:
    scf
    ret
net_uint_done:
    ld a,(net_digits)
    or a
    jp z,net_parse_fail
    or a
    ret
net_config: db 0
net_ip_start: dw 0
net_port_start: dw 0
net_octet_ptr: dw 0
net_octets: db 0
net_digit: db 0
net_digits: db 0
net_host: ds 32
net_params:
    db 0,0,0,0
    dw 0,&FFFF,0
    db 0
net_note_config: dm "[NET] Alvo LAN configurado. ^Q publica; ^W transmite."
    db 0
net_note_config_bad: dm "[NET] Argumentos invalidos. Use MSXCHAT IP-PRIVADO PORTA."
    db 0

net_title: dm "MSX CHATGPT 80x24 | LAN CONFIG."
    db 0

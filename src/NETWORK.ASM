; NETWORK.ASM -- synchronous bounded LAN transaction, Ctrl+W.
; All disk/API calls run after io_begin; no stack/helper installation.
command_network:
    ld a,(net_owned)
    or a
    jp nz,net_recover_owned
    ld a,(net_config)
    cp 1
    ld hl,net_note_config_bad
    jp nz,storage_note
    ld a,(storage_locked)
    or a
    ld hl,note_locked
    jp nz,storage_note
    ld hl,(pending_id)
    ld a,h
    or l
    ld hl,note_no_pending
    jp z,storage_note
    call io_begin
    ld hl,(pending_id)
    ld (selected_id),hl
    ld a,2
    call make_name
    call dos_exists
    jp c,net_exchange
    call io_end
    jp command_response
net_exchange:
    xor a
    ld (net_processing),a
    ld hl,net_console_busy
    call net_console
    xor a
    ld (net_owned),a
    ld (net_arg_saved),a
    ld (net_eof),a
    ld (net_api_error),a
    ld (net_cleanup_error),a
    ld (net_ext_ready),a
    ld hl,0
    ld (net_helper_ptr),hl
    ld (net_rx_count),hl
    ld a,7
    ld (net_error),a
    ld a,1
    call make_name
    call json_load
    jp c,net_failed
    call validate_request
    jp c,net_failed
    ld a,1
    call make_name
    call dos_open
    jp c,net_failed
    ld hl,(file_remaining)
    ld (net_request_length),hl
    ; The REQ stays open until its bytes have all been queued.
    ld a,1
    ld (net_error),a
    call net_init
    ld a,(net_ext_ready)
    or a
    jp z,net_failed
    ld hl,net_id_tcp
    ld (net_api_id),hl
    call net_count_api
    or a
    jp z,net_failed
    call net_select_api
    jp c,net_failed
    xor a
    call net_call_api
    or a
    jp nz,net_api_failed
    ld a,d
    cp 1
    jp nz,net_failed
    ld a,1
    ld b,a
    call net_call_api
    or a
    jp nz,net_api_failed
    bit 3,l
    jp z,net_failed
    bit 3,d
    jp nz,net_failed
    ld hl,net_params
    ld de,NETPARAM
    ld bc,11
    ldir
    ld hl,(JIFFY)
    ld (net_total_tick),hl
    call net_timer
    ld hl,NETPARAM
    ld a,13
    call net_call_api
    or a
    jp nz,net_api_failed
    ld a,b
    ld (net_connection),a
    ld a,1
    ld (net_owned),a
net_open_wait:
    call net_poll
    jp c,net_failed
    call net_state
    jp c,net_failed
    cp 4
    jp z,net_send_request
    cp 7
    jp z,net_send_request
    cp 2
    jp z,net_open_wait
    cp 3
    jp z,net_open_wait
    ld a,3
    jp net_fail_code
net_send_request:
    call http_request_header
    jp c,net_failed
net_request_block:
    ld hl,0
    ld (net_tx_count),hl
net_request_fill:
    call read_byte
    jp c,net_request_read_end
    ld hl,(net_tx_count)
    ld de,NETTX
    add hl,de
    ld (hl),a
    ld hl,(net_tx_count)
    inc hl
    ld (net_tx_count),hl
    ld a,h
    cp 1
    jp nz,net_request_fill
    call net_send
    jp c,net_failed
    jp net_request_block
net_request_read_end:
    ld a,(io_error)
    or a
    jp nz,net_disk_failed
    ld hl,(net_tx_count)
    ld a,h
    or l
    jp z,net_request_sent
    call net_send
    jp c,net_failed
net_request_sent:
    call dos_close
    jp c,net_disk_failed
    call net_timer
    call http_receive_headers
    jp c,net_failed
    ld a,8
    call make_name
    call dos_create
    jp c,net_disk_failed
net_body_loop:
    call net_receive_byte
    jp c,net_failed
    call write_byte
    jp c,net_disk_failed
    ld hl,(http_length)
    dec hl
    ld (http_length),hl
    ld a,h
    or l
    jp nz,net_body_loop
    ; Reject extra bytes and require orderly peer EOF before publication.
    call net_receive_byte
    jp nc,net_http_failed
    ld a,(net_eof)
    or a
    jp z,net_failed
    call writer_finish
    jp c,net_disk_failed
    call net_timer
    ld a,(net_connection)
    ld b,a
    ld a,14
    call net_call_api
    or a
    jp nz,net_api_failed
net_close_wait:
    call net_poll
    jp c,net_failed
    ld a,(net_connection)
    ld b,a
    ld hl,0
    ld a,16
    call net_call_api
    cp 11
    jp z,net_closed
    or a
    jp nz,net_api_failed
    jp net_close_wait
net_closed:
    xor a
    ld (net_owned),a
    ld a,8
    call make_name
    call json_load
    jp c,net_json_failed
    call validate_response
    jp c,net_json_failed
    ld a,8
    call make_name
    call remember_old_name
    ld a,2
    call make_name
    ex de,hl
    ld hl,old_name
    call dos_rename
    jp c,net_disk_failed
    call net_restore_arg
    call io_end
    ; Existing importer writes ACK before displaying, preserving idempotency.
    jp command_response

net_send:
    call net_timer
net_send_retry:
    call net_poll
    ret c
    ld a,(net_connection)
    ld b,a
    ld c,1
    ld de,NETTX
    ld hl,(net_tx_count)
    ld a,17
    call net_call_api
    or a
    ret z
    cp 13
    jp z,net_send_retry
    jp net_api_fail_return
net_state:
    ld a,(net_connection)
    ld b,a
    ld hl,0
    ld a,16
    call net_call_api
    or a
    jp nz,net_api_fail_return
    ld a,b
    or a
    ret
net_timer:
    ld hl,(JIFFY)
    ld (net_start_tick),hl
    ret
net_poll:
    call keyboard_poll
    cp 27
    jp z,net_cancel_return
    cp 3
    jp z,net_cancel_return
    ld hl,(JIFFY)
    ld de,(net_start_tick)
    or a
    sbc hl,de
    ld de,1200
    or a
    sbc hl,de
    jp nc,net_timeout_return
    ld hl,(JIFFY)
    ld de,(net_total_tick)
    or a
    sbc hl,de
    ld de,3600
    or a
    sbc hl,de
    jp nc,net_timeout_return
    ld a,29
    call net_call_api
    or a
    jp nz,net_api_fail_return
    ret
net_cancel_return:
    ld a,5
    jp net_error_return
net_timeout_return:
    ld a,4
    jp net_error_return
net_api_fail_return:
    ld (net_api_error),a
    ld a,3
net_error_return:
    ld (net_error),a
    scf
    ret
; CF=EOF/error; net_eof disambiguates. Byte result A.
net_receive_byte:
    ld hl,(net_rx_count)
    ld a,h
    or l
    jp nz,net_receive_buffered
net_receive_wait:
    call net_poll
    ret c
    ld a,(net_connection)
    ld b,a
    ld de,NETRX
    ld hl,256
    ld a,18
    call net_call_api
    or a
    jp nz,net_api_fail_return
    ld a,h
    or l
    jp nz,net_http_fail_return
    ld h,b
    ld l,c
    ld a,h
    or l
    jp z,net_receive_empty
    ld de,256
    or a
    sbc hl,de
    jp c,net_receive_count_ok
    jp nz,net_http_fail_return
net_receive_count_ok:
    ld h,b
    ld l,c
    ld (net_rx_count),hl
    ld hl,NETRX
    ld (net_rx_pointer),hl
net_receive_buffered:
    ld hl,(net_rx_count)
    dec hl
    ld (net_rx_count),hl
    ld hl,(net_rx_pointer)
    ld a,(hl)
    inc hl
    ld (net_rx_pointer),hl
    or a
    ret
net_receive_empty:
    call net_state
    ret c
    cp 4
    jp z,net_receive_wait
    cp 7
    jp nz,net_http_fail_return
    ld a,6
    ld (net_error),a
    ld a,1
    ld (net_eof),a
    scf
    ret
net_http_fail_return:
    ld a,6
    jp net_error_return
net_http_failed:
    ld a,6
    jp net_fail_code
net_disk_failed:
    ld a,7
    jp net_fail_code
net_json_failed:
    ld a,8
net_fail_code:
    ld (net_error),a
    jp net_failed
net_api_failed:
    call net_api_fail_return
net_failed:
    ld a,(net_owned)
    or a
    jp z,net_cleanup_arg
    call net_abort_owned
net_cleanup_arg:
    call dos_close
    call net_restore_arg
    call io_end
    ld a,(net_error)
    cp 9
    jp nz,net_show_failure
    ld a,(net_owned)
    or a
    jp nz,net_show_failure
    ld a,1
    ld (net_processing),a
    ld hl,net_note_processing
    jp storage_note
net_show_failure:
    ld hl,net_note_failed
    call storage_note
    ld hl,HEX_BUFFER
    ld a,(net_error)
    call hex_byte_at
    ld a,47
    ld (hl),a
    inc hl
    ld a,(net_api_error)
    call hex_byte_at
    ld a,47
    ld (hl),a
    inc hl
    ld a,(net_cleanup_error)
    call hex_byte_at
    xor a
    ld (hl),a
    ld hl,HEX_BUFFER
    jp storage_note
net_restore_arg:
    ld a,(net_arg_saved)
    or a
    ret z
    ld hl,net_saved_arg
    ld de,ARG
    ld bc,16
    ldir
    xor a
    ld (net_arg_saved),a
    ret

net_owned: db 0
net_connection: db 0
net_eof: db 0
net_error: db 0
net_api_error: db 0
net_cleanup_error: db 0
net_total_tick: dw 0
net_request_length: dw 0
net_tx_count: dw 0
net_rx_count: dw 0
net_rx_pointer: dw 0
net_note_failed: dm "[NET] Falha; editor/pedido mantidos. Categoria/UNAPI/cleanup HEX:"
    db 0

net_abort_owned:
    ld a,(net_connection)
    ld b,a
    ld a,15
    call net_call_api
    cp 11
    jp z,net_abort_clear
    or a
    jp nz,net_abort_record
net_abort_clear:
    xor a
    ld (net_owned),a
net_abort_record:
    ld (net_cleanup_error),a
    ret
net_recover_owned:
    call io_begin
    call net_abort_owned
    call io_end
    ld hl,net_note_cleanup
    jp storage_note
net_exit_cleanup:
    ld a,(net_owned)
    or a
    ret z
    call net_abort_owned
    ld a,(net_owned)
    or a
    ret z
    ld hl,net_console_cleanup
net_console:
    ld a,(hl)
    or a
    ret z
    push hl
    ld e,a
    ld c,6
    call BDOS
    pop hl
    inc hl
    jp net_console
net_console_busy: dm "NET: gateway on PC. Esc cancels local wait, not API work."
    db 13,10,0
net_console_cleanup: dm "NET: abort failed. Check stack connections before retry."
    db 13,10,0
net_note_cleanup: dm "[NET] Cleanup repetido. Se a conexao persistir, revise a pilha."
    db 0

net_note_processing: dm "[API] Processando. Auto/^W consulta o mesmo pedido no PC."
    db 0

net_processing: db 0

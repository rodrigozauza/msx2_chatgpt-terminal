; BROWSER.ASM -- read-only, paged history over immutable Phase 2 records.
; One decoded question (B400) and reply (A800), never the full history.
history_open:
    call io_begin
    ld hl,(history_ceiling)
    ld (history_candidate),hl
    ld a,255
    ld (history_direction),a
    call history_find
    jp c,history_none
    call history_cache
    call io_end
    ld a,1
    ld (history_active),a
    jp history_new_view
history_none:
    call io_end
    ld hl,history_empty
    jp storage_note
history_close:
    xor a
    ld (history_active),a
    call overlay_restore
    ld a,FOOTER_ROW
    ld hl,footer_text
    call put_line
    ld hl,(JIFFY)
    ld (poll_tick),hl
    jp editor_update

; Keys are modal: arbitrary typing and submit do not alter the editor.
history_key:
    cp 27
    jp z,history_close
    cp 25
    jp z,history_close
    cp 29
    jp z,history_previous
    cp 28
    jp z,history_next
    cp 30
    jp z,history_up
    cp 31
    jp z,history_down
    cp 21
    jp z,history_page_up
    cp 14
    jp z,history_page_down
    cp 1
    jp z,history_top
    cp 11
    jp z,history_top
    cp 5
    jp z,history_bottom
    cp 6
    jp z,history_recall
    ret
history_previous:
    ld a,255
    jp history_move
history_next:
    ld a,1
history_move:
    ld (history_direction),a
    ld hl,(history_id)
    ld (history_candidate),hl
    call history_step
    ret c
    call io_begin
    call history_find
    jp c,history_move_end
    call history_cache
    call io_end
    jp history_new_view
history_move_end:
    call io_end
    jp history_draw
; Bounds checked before any name construction. CF means end.
history_step:
    ld hl,(history_candidate)
    ld a,(history_direction)
    cp 1
    jp z,history_step_forward
    dec hl
    ld a,h
    or l
    jp z,history_end
    ld (history_candidate),hl
    or a
    ret
history_step_forward:
    inc hl
    ld a,h
    or l
    jp z,history_end
    ld de,(history_ceiling)
    push hl
    or a
    sbc hl,de
    pop hl
    jp c,history_step_ok
    jp nz,history_end
history_step_ok:
    ld (history_candidate),hl
    or a
    ret
history_end:
    scf
    ret
history_find:
    ld hl,(history_candidate)
    ld a,h
    or l
    jp z,history_end
    ld (selected_id),hl
    ld a,1
    call make_name
    call dos_exists
    ret nc
    call history_step
    ret c
    jp history_find

; Called with DOS video active. Only validated content may reach the view.
history_cache:
    ld hl,(history_candidate)
    ld (history_id),hl
    ld (selected_id),hl
    ld hl,0
    ld (history_top_row),hl
    ld (history_length),hl
    xor a
    ld (HISTORY_TEXT),a
    ld (REPLY_BUFFER),a
    ld (P_ERROR),a
    ld (history_valid),a
    ld (history_has_reply),a
    ld hl,history_bad_request
    ld (history_status),hl
    ld a,1
    call make_name
    call json_load
    jp c,history_clear_reply
    call validate_request
    jp c,history_clear_reply
    ld hl,(FIELD_LENGTHS+8)
    ld (history_length),hl
    inc hl
    ld b,h
    ld c,l
    ld hl,MSG_BUFFER
    ld de,HISTORY_TEXT
    ldir
    ld a,1
    ld (history_valid),a
    ld hl,history_pending
    ld (history_status),hl
    ; Cancelled records remain visible, but never consume a late RSP.
    ld a,6
    call make_name
    call dos_exists
    jp c,history_check_ack
    ld a,6
    call make_name
    call json_load
    jp c,history_bad_link
    call validate_cancel
    jp c,history_bad_link
    ld a,3
    call make_name
    call dos_exists
    jp nc,history_bad_link
    ld hl,history_cancelled
    ld (history_status),hl
    jp history_clear_reply
history_check_ack:
    ld a,3
    call make_name
    call dos_exists
    jp c,history_clear_reply
    ld hl,history_bad_receipt
    ld (history_status),hl
    ld a,3
    call make_name
    call json_load
    jp c,history_bad_link
    call validate_ack
    jp c,history_bad_link
    ld hl,P_RESPONSE
    ld de,history_ack_id
    ld bc,9
    ldir
    ld hl,P_ERROR
    ld de,history_ack_error
    ld bc,32
    ldir
    ld a,2
    call make_name
    call json_load
    jp c,history_bad_link
    call validate_response
    jp c,history_bad_link
    ld hl,P_RESPONSE
    ld de,history_ack_id
    call strings_equal
    jp nz,history_bad_link
    ld hl,P_ERROR
    ld de,history_ack_error
    call strings_equal
    jp nz,history_bad_link
    ld a,1
    ld (history_has_reply),a
    ld hl,history_complete
    ld (history_status),hl
    ld a,(P_ERROR)
    or a
    ret z
    ld hl,history_error
    ld (history_status),hl
    ret
history_bad_link:
    ld hl,history_bad_receipt
    ld (history_status),hl
history_clear_reply:
    xor a
    ld (REPLY_BUFFER),a
    ld (P_ERROR),a
    ret

history_new_view:
    ld hl,0
    ld (history_top_row),hl
    jp history_draw
history_up:
    ld hl,(history_top_row)
    ld a,h
    or l
    ret z
    dec hl
    ld (history_top_row),hl
    jp history_draw
history_down:
    ld hl,(history_top_row)
    inc hl
    ld (history_top_row),hl
    jp history_draw
history_page_up:
    ld hl,(history_top_row)
    ld de,HISTORY_VIEW_ROWS
    or a
    sbc hl,de
    jp nc,history_set_top
    ld hl,0
history_set_top:
    ld (history_top_row),hl
    jp history_draw
history_page_down:
    ld hl,(history_top_row)
    ld de,HISTORY_VIEW_ROWS
    add hl,de
    jp history_set_top
history_top:
    ld hl,0
    jp history_set_top
history_bottom:
    ld hl,(history_max_top)
    jp history_set_top
history_recall:
    ld a,(history_valid)
    or a
    ret z
    ld hl,(editor_length)
    ld a,h
    or l
    jp nz,history_recall_refuse
    ld hl,(history_length)
    ld (editor_length),hl
    ld (editor_cursor),hl
    inc hl
    ld b,h
    ld c,l
    ld hl,HISTORY_TEXT
    ld de,EDITOR
    ldir
    call history_close
    ld hl,history_recalled
    jp storage_note
history_recall_refuse:
    ld a,1
    ld hl,history_editor_busy
    jp put_line

; Stream six bounded strings. Labels provide USER/CHATGPT identity.
history_stream_reset:
    xor a
    ld (history_block),a
    ld hl,history_user_label
    ld (history_pointer),hl
    ret
history_stream_next:
    ld hl,(history_pointer)
    ld a,(hl)
    or a
    jp z,history_stream_switch
    inc hl
    ld (history_pointer),hl
    or a
    ret
history_stream_switch:
    ld a,(history_block)
    inc a
    ld (history_block),a
    cp 6
    jp nc,history_end
    cp 2
    jp nz,history_stream_check_error
    ld a,(history_has_reply)
    or a
    jp nz,history_stream_select
    ld a,3
    ld (history_block),a
    jp history_stream_switch
history_stream_check_error:
    cp 4
    jp nz,history_stream_select
    ld a,(P_ERROR)
    or a
    jp nz,history_stream_select
    ld a,5
    ld (history_block),a
    jp history_stream_switch
history_stream_select:
    ld a,(history_block)
    ld l,a
    ld h,0
    add hl,hl
    ld de,history_blocks
    add hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (history_pointer),de
    jp history_stream_next

history_draw:
    ; Back up live terminal only once, after any io_begin restored it.
    ld a,(overlay_mode)
    cp 3
    jp z,history_draw_start
    call overlay_save
    ld a,3
    ld (overlay_mode),a
history_draw_start:
    ld hl,GRID+2*GRID_STRIDE
    ld bc,HISTORY_VIEW_ROWS*GRID_STRIDE
    ld a,32
    call fill_memory
    ld hl,ROWCOLORS+1
    ld bc,OVERLAY_ROWS
    ld a,&F1
    call fill_memory
    call layout_reset
    call history_stream_reset
history_render_loop:
    call history_stream_next
    jp c,history_render_done
    ld (history_char),a
    cp 10
    call nz,history_place
    ld a,(history_char)
    call advance_layout
    jp history_render_loop
history_render_done:
    ld hl,(layout_row)
    inc hl
    ld (history_rows),hl
    ld de,HISTORY_VIEW_ROWS
    or a
    sbc hl,de
    jp nc,history_have_max
    ld hl,0
history_have_max:
    ld (history_max_top),hl
    ld de,(history_top_row)
    or a
    sbc hl,de
    jp nc,history_header
    ld hl,(history_max_top)
    ld (history_top_row),hl
    jp history_draw_start
history_header:
    ld a,1
    ld hl,history_header_text
    call put_line
    ld hl,(history_id)
    ld (selected_id),hl
    ld a,1
    call make_name
    ld hl,id_ascii
    ld de,GRID+GRID_STRIDE+3
    ld bc,8
    ldir
    ld hl,GRID+GRID_STRIDE+14
    ld de,(history_top_row)
    call hex_at
    ld hl,GRID+GRID_STRIDE+19
    ld de,(history_rows)
    call hex_at
    ld hl,(history_status)
    ld de,GRID+GRID_STRIDE+24
    ld b,8
history_status_copy:
    ld a,(hl)
    or a
    jp z,history_footer_draw
    ld (de),a
    inc hl
    inc de
    djnz history_status_copy
history_footer_draw:
    ld a,&71
    ld (ROWCOLORS+1),a
    ld a,FOOTER_ROW
    ld hl,history_footer_text
    call put_line
    jp mark_all

history_place:
    ld hl,(layout_row)
    ld de,(history_top_row)
    or a
    sbc hl,de
    ret c
    ld a,h
    or a
    ret nz
    ld a,l
    cp HISTORY_VIEW_ROWS
    ret nc
    call grid_row_offset
    ld de,GRID+2*GRID_STRIDE
    add hl,de
    ld a,(layout_col)
    ld e,a
    ld d,0
    add hl,de
    ld a,(history_char)
    ld (hl),a
    ret

history_active: db 0
history_id: dw 0
history_ceiling: dw 0
history_candidate: dw 0
history_direction: db 255
history_top_row: dw 0
history_rows: dw 0
history_max_top: dw 0
history_status: dw history_pending
history_length: dw 0
history_valid: db 0
history_has_reply: db 0
history_block: db 0
history_pointer: dw 0
history_char: db 0
history_ack_id: ds 9
history_ack_error: ds 32
history_blocks:
    dw history_user_label,HISTORY_TEXT,history_reply_label,REPLY_BUFFER,history_error_label,P_ERROR
history_user_label: dm "[USER]"
    db 10,0
history_reply_label: db 10
    dm "[CHATGPT / RESPOSTA LOCAL]"
    db 10,0
history_error_label: db 10
    dm "[ERROR_CODE]"
    db 10,0
history_header_text: dm "ID=00000000 L=0000/0000   "
    db 0
history_footer_text: dm "Esc <> pedido ^U^N pag ^F usar"
    db 0
history_pending: dm "PENDENTE"
    db 0
history_complete: dm "PRONTO"
    db 0
history_error: dm "ERRO API"
    db 0
history_cancelled: dm "CANCEL."
    db 0
history_bad_request: dm "INV.REQ"
    db 0
history_bad_receipt: dm "INV.RSP"
    db 0
history_empty: dm "[HIST] Nenhuma pergunta disponivel neste volume."
    db 0
history_editor_busy: dm "Editor ocupado. Esc volta; ^L."
    db 0
history_recalled: dm "[HIST] Pergunta copiada ao editor. Nada enviado."
    db 0

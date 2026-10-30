; CANCEL.ASM -- explicit two-key local cancellation, no network action.
command_cancel:
    ld a,(storage_locked)
    or a
    ld hl,note_locked
    jp nz,storage_note
    ld hl,(pending_id)
    ld a,h
    or l
    ld hl,note_no_pending
    jp z,storage_note
    ld a,(cancel_armed)
    or a
    jp nz,cancel_commit
    ld a,1
    ld (cancel_armed),a
    ld hl,note_cancel_confirm
    jp storage_note
cancel_commit:
    xor a
    ld (cancel_armed),a
    call io_begin
    ld hl,(pending_id)
    ld (selected_id),hl
    ld a,1
    call make_name
    call json_load
    jp c,cancel_failed
    call validate_request
    jp c,cancel_failed
    call output_defaults
    ld hl,id_ascii
    ld (out_request),hl
    ld hl,state_cancelled
    ld (out_state),hl
    ld hl,empty_value
    ld (out_message),hl
    ld a,7
    call make_name
    call json_write
    jp c,cancel_failed
    ld a,7
    call make_name
    call json_load
    jp c,cancel_failed
    call validate_cancel
    jp c,cancel_failed
    ld a,7
    call make_name
    call remember_old_name
    ld a,6
    call make_name
    ex de,hl
    ld hl,old_name
    call dos_rename
    jp c,cancel_failed
    ld hl,0
    ld (pending_id),hl
    xor a
    ld (net_processing),a
    ld hl,note_cancelled
    jp storage_command_end
cancel_failed:
    ld hl,note_cancel_failed
    jp storage_command_end
validate_cancel:
    call validate_expected
    ret c
    ld hl,P_STATE
    ld de,state_cancelled
    call strings_equal
    jp nz,schema_fail
    call validate_empty_message
    ret c
    jp validate_empty_response
cancel_armed: db 0
state_cancelled: dm "cancelled"
    db 0
note_cancel_confirm: dm "[SD] ^X novamente cancela pedido local; outra tecla desiste."
    db 0
note_cancelled: dm "[SD] Cancelamento local gravado. Editor mantido."
    db 0
note_cancel_failed: dm "[SD] Cancelamento falhou. Pedido continua pendente."
    db 0

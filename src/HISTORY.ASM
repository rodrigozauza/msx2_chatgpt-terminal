; HISTORY.ASM -- Phase 3 durable offline artifacts, one pending request.
; Immutable .ID reservations prevent reuse. .REQ/.RSP/.ACK are committed names.
storage_boot:
    call storage_scan
    call load_draft
    call dos_reset_dta
    ld hl,(JIFFY)
    ld (poll_tick),hl
    ret
storage_show_boot:
    ld a,(draft_loaded)
    or a
    ld hl,note_restored
    call nz,storage_note
    ld hl,(pending_id)
    ld a,h
    or l
    jp z,boot_no_pending
    ld hl,note_pending
    call storage_note
    ld hl,(pending_id)
    ld (selected_id),hl
    ld a,1
    call make_name
    ld hl,id_ascii
    call storage_note
boot_no_pending:
    ld a,(draft_problem)
    or a
    ld hl,note_draft_problem
    call nz,storage_note
    ld a,(storage_locked)
    or a
    ld hl,note_locked
    call nz,storage_note
    ret

; Disk calls happen with DOS video restored. Native DOS abort is thus safe for video.
io_begin:
    call overlay_restore
    call screen_leave
    ret
io_end:
    call dos_close
    call dos_reset_dta
    call mark_all
    call screen_enter
    ld hl,(JIFFY)
    ld (blink_tick),hl
    ld (poll_tick),hl
    ret
storage_note:
    ld (note_pointer),hl
    call overlay_restore
    ld a,(term_col)
    or a
    call nz,term_newline
    ld a,&71
    ld (term_color),a
    ld hl,(note_pointer)
    call term_string
    ld a,10
    call term_char
    ld a,&F1
    ld (term_color),a
    ret
command_save:
    call io_begin
    call save_draft
    ld hl,note_saved
    jp nc,storage_command_end
    ld hl,note_file_error
    jp storage_command_end
command_load:
    call io_begin
    call load_draft
    ld hl,note_restored
    jp nc,command_load_done
    ld hl,note_no_draft
command_load_done:
    ld (command_note),hl
    call editor_update
    ld hl,(command_note)
    jp storage_command_end
command_submit:
    ld hl,(editor_length)
    ld a,h
    or l
    ret z
    call io_begin
    call storage_scan
    ld a,(storage_locked)
    or a
    jp nz,submit_locked
    ld hl,(pending_id)
    ld a,h
    or l
    jp nz,submit_pending
    call save_draft
    jp c,submit_error
    ld hl,(next_id)
    ld (selected_id),hl
    xor a
    call make_name
    call dos_create
    jp c,submit_error
    ld hl,id_ascii
    call emit_z
    jp c,submit_error
    call writer_finish
    jp c,submit_error
    call output_defaults
    ld hl,id_ascii
    ld (out_request),hl
    ld hl,state_pending
    ld (out_state),hl
    ld a,4
    call make_name
    call json_write
    jp c,submit_error
    ld a,4
    call make_name
    call json_load
    jp c,submit_error
    call validate_request
    jp c,submit_error
    call compare_message_editor
    jp c,submit_error
    ld a,4
    call make_name
    call remember_old_name
    ld a,1
    call make_name
    ex de,hl
    ld hl,old_name
    call dos_rename
    jp c,submit_error
    ld hl,(selected_id)
    ld (pending_id),hl
    ld (history_ceiling),hl
    xor a
    ld (net_processing),a
    ld hl,note_queued
    jp storage_command_end
submit_error:
    ld hl,note_file_error
    jp storage_command_end
submit_locked:
    ld hl,note_locked
    jp storage_command_end
submit_pending:
    ld hl,note_pending
storage_command_end:
    ld (command_note),hl
    call io_end
    ld hl,(command_note)
    call storage_note
    ld hl,(pending_id)
    ld a,h
    or l
    ret z
    ld (selected_id),hl
    ld a,1
    call make_name
    ld hl,id_ascii
    jp storage_note

command_response:
    xor a
    ld (auto_call),a
    jp response_begin
storage_auto_poll:
    ld a,(history_active)
    or a
    ret nz
    ld a,(cancel_armed)
    or a
    ret nz
    ld a,(storage_locked)
    or a
    ret nz
    ld a,(auto_enabled)
    or a
    ret z
    ld hl,(pending_id)
    ld a,h
    or l
    ret z
    ld hl,(JIFFY)
    ld de,(poll_tick)
    or a
    sbc hl,de
    ld de,600
    or a
    sbc hl,de
    ret c
    ld a,(net_processing)
    or a
    jp nz,command_network
    ld a,1
    ld (auto_call),a
response_begin:
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
    jp c,response_not_ready
    ld a,2
    call make_name
    call json_load
    jp c,response_invalid
    call validate_response
    jp c,response_invalid
    ; ACK is staged, closed and renamed before any display.
    call output_defaults
    ld hl,empty_value
    ld (out_message),hl
    ld hl,id_ascii
    ld (out_request),hl
    ld hl,state_ack
    ld (out_state),hl
    ld hl,P_RESPONSE
    ld (out_response),hl
    ld hl,P_ERROR
    ld (out_error),hl
    ld a,5
    call make_name
    call json_write
    jp c,response_invalid
    ld a,5
    call make_name
    call remember_old_name
    ld a,3
    call make_name
    ex de,hl
    ld hl,old_name
    call dos_rename
    jp c,response_invalid
    ld hl,(selected_id)
    ld (last_response_id),hl
    ld hl,0
    ld (pending_id),hl
    call io_end
    jp show_response
response_invalid:
    xor a
    ld (auto_enabled),a
    ld hl,note_bad_response
    jp storage_command_end
response_not_ready:
    call io_end
    ld a,(auto_call)
    or a
    ret nz
    ld hl,note_wait
    jp storage_note
command_review:
    ld hl,(last_response_id)
    ld a,h
    or l
    ld hl,note_no_response
    jp z,storage_note
    call io_begin
    ld hl,(last_response_id)
    ld (selected_id),hl
    ld a,2
    call make_name
    call json_load
    jp c,response_invalid
    call validate_response
    jp c,response_invalid
    call io_end
    ld hl,note_review
    call storage_note
show_response:
    ld hl,response_label
    call storage_note
    ld hl,id_ascii
    call storage_note
    ld hl,REPLY_BUFFER
    call term_string
    ld a,10
    call term_char
    ld hl,P_ERROR
    ld a,(hl)
    or a
    ret z
    jp storage_note
command_auto:
    ld a,(auto_enabled)
    xor 1
    ld (auto_enabled),a
    ld hl,note_auto_off
    jp z,storage_note
    ld hl,note_auto_on
    jp storage_note

; No application operation deletes reservation markers or published messages.
storage_scan:
    xor a
    ld (storage_locked),a
    ld hl,0
    ld (pending_id),hl
    ld (last_response_id),hl
    ld (history_ceiling),hl
    ld hl,1
    ld (scan_id),hl
scan_loop:
    ld hl,(scan_id)
    ld (selected_id),hl
    xor a
    call make_name
    call dos_exists
    jp c,scan_free_marker
    ld hl,(scan_id)
    ld (history_ceiling),hl
    ld a,1
    call make_name
    call dos_exists
    jp c,scan_next
    ld a,1
    call make_name
    call json_load
    jp c,scan_lock
    call validate_request
    jp c,scan_lock
    ld a,6
    call make_name
    call dos_exists
    jp c,scan_check_ack
    ld a,6
    call make_name
    call json_load
    jp c,scan_lock
    call validate_cancel
    jp c,scan_lock
    ld a,3
    call make_name
    call dos_exists
    jp nc,scan_lock
    jp scan_next
scan_check_ack:
    ld a,3
    call make_name
    call dos_exists
    jp c,scan_pending
    ld a,3
    call make_name
    call json_load
    jp c,scan_lock
    call validate_ack
    jp c,scan_lock
    ld hl,(scan_id)
    ld (last_response_id),hl
    jp scan_next
scan_pending:
    ld hl,(pending_id)
    ld a,h
    or l
    jp nz,scan_lock
    ld hl,(scan_id)
    ld (pending_id),hl
scan_next:
    ld hl,(scan_id)
    inc hl
    ld (scan_id),hl
    ld a,h
    or l
    jp nz,scan_loop
    jp scan_lock
scan_free_marker:
    ; An orphan published artifact without its marker is ambiguous, never reused.
    ld a,1
    call make_name
    call dos_exists
    jp nc,scan_lock
    ld a,2
    call make_name
    call dos_exists
    jp nc,scan_lock
    ld a,3
    call make_name
    call dos_exists
    jp nc,scan_lock
    ld a,6
    call make_name
    call dos_exists
    jp nc,scan_lock
    ld hl,(scan_id)
    ld (next_id),hl
    or a
    ret
scan_lock:
    ld a,1
    ld (storage_locked),a
    ld a,3
    ld (last_error),a
    scf
    ret

load_draft:
    xor a
    ld (draft_loaded),a
    ld (draft_problem),a
    ld hl,draft_name
    call dos_exists
    jp c,load_backup
    ld hl,draft_name
    call json_load
    jp c,load_draft_bad
    call validate_draft
    jp nc,load_draft_copy
load_draft_bad:
    ld a,1
    ld (draft_problem),a
load_backup:
    ld hl,backup_name
    call dos_exists
    ret c
    ld hl,backup_name
    call json_load
    ret c
    call validate_draft
    ret c
load_draft_copy:
    ld hl,(FIELD_LENGTHS+8)
    ld (editor_length),hl
    ld (editor_cursor),hl
    inc hl
    ld b,h
    ld c,l
    ld hl,MSG_BUFFER
    ld de,EDITOR
    ldir
    ld hl,0
    ld (view_top),hl
    xor a
    ld (buffer_full),a
    ld a,1
    ld (draft_loaded),a
    or a
    ret
save_draft:
    call output_defaults
    ld hl,draft_tmp
    call json_write
    ret c
    ld hl,draft_tmp
    call json_load
    ret c
    call validate_draft
    ret c
    call compare_message_editor
    ret c
    ld hl,draft_name
    call dos_exists
    jp c,draft_publish
    ; Do not replace a valid backup with a corrupt main generation.
    ld hl,draft_name
    call json_load
    ret c
    call validate_draft
    ret c
    ld hl,backup_name
    call dos_exists
    jp c,draft_rotate
    ld hl,backup_name
    call dos_delete
    ret c
draft_rotate:
    ld hl,draft_name
    ld de,backup_name
    call dos_rename
    ret c
draft_publish:
    ld hl,draft_tmp
    ld de,draft_name
    jp dos_rename
compare_message_editor:
    ld hl,(FIELD_LENGTHS+8)
    ld de,(editor_length)
    or a
    sbc hl,de
    jp nz,schema_fail
    ld hl,MSG_BUFFER
    ld de,EDITOR
    call strings_equal
    jp nz,schema_fail
    or a
    ret
output_defaults:
    ld hl,zero_id
    ld (out_request),hl
    ld hl,state_draft
    ld (out_state),hl
    ld hl,EDITOR
    ld (out_message),hl
    ld hl,empty_value
    ld (out_response),hl
    ld (out_reply),hl
    ld (out_error),hl
    ret

; A=extension index, builds exact 8.3 name plus the matching JSON ID.
make_name:
    ld (extension_index),a
    ld hl,name_buffer
    ld bc,8
    ld a,48
    call fill_memory
    ld hl,name_buffer+4
    ld de,(selected_id)
    call hex_at
    ld hl,name_buffer
    ld de,id_ascii
    ld bc,8
    ldir
    xor a
    ld (id_ascii+8),a
    ld a,(extension_index)
    ld l,a
    ld h,0
    ld d,h
    ld e,l
    add hl,hl
    add hl,de
    ld de,extension_table
    add hl,de
    ld de,name_buffer+8
    ld bc,3
    ldir
    ld hl,name_buffer
    ret
remember_old_name:
    ld de,old_name
    ld bc,11
    ldir
    ret

validate_common:
    ld hl,P_PROTOCOL
    ld de,protocol_value
    call strings_equal
    jp nz,schema_fail
    ld hl,P_CONVERSATION
    ld de,conversation_value
    call strings_equal
    jp nz,schema_fail
    ret
validate_expected:
    call validate_common
    ret c
    ld hl,P_REQUEST
    ld de,id_ascii
    call strings_equal
    jp nz,schema_fail
    or a
    ret
validate_draft:
    call validate_common
    ret c
    ld hl,P_REQUEST
    ld de,zero_id
    call strings_equal
    jp nz,schema_fail
    ld hl,P_STATE
    ld de,state_draft
    call strings_equal
    jp nz,schema_fail
    jp validate_empty_response
validate_request:
    call validate_expected
    ret c
    ld hl,P_STATE
    ld de,state_pending
    call strings_equal
    jp nz,schema_fail
    ld hl,(FIELD_LENGTHS+8)
    ld a,h
    or l
    jp z,schema_fail
validate_empty_response:
    ld a,(P_RESPONSE)
    or a
    jp nz,schema_fail
    ld hl,(FIELD_LENGTHS+12)
    ld a,h
    or l
    jp nz,schema_fail
    ld a,(P_ERROR)
    or a
    jp nz,schema_fail
    or a
    ret
validate_ack:
    call validate_expected
    ret c
    ld hl,P_STATE
    ld de,state_ack
    call strings_equal
    jp nz,schema_fail
    call validate_empty_message
    ret c
    ld hl,(FIELD_LENGTHS+12)
    ld a,h
    or l
    jp nz,schema_fail
    jp validate_response_id
validate_response:
    call validate_expected
    ret c
    call validate_empty_message
    ret c
    call validate_response_id
    ret c
    ld hl,P_STATE
    ld de,state_completed
    call strings_equal
    jp nz,validate_error_state
    ld a,(P_ERROR)
    or a
    jp nz,schema_fail
    ld hl,(FIELD_LENGTHS+12)
    ld a,h
    or l
    jp z,schema_fail
    or a
    ret
validate_error_state:
    ld hl,P_STATE
    ld de,state_error
    call strings_equal
    jp nz,schema_fail
    ld a,(P_ERROR)
    or a
    jp z,schema_fail
    or a
    ret
validate_empty_message:
    ld hl,(FIELD_LENGTHS+8)
    ld a,h
    or l
    jp nz,schema_fail
    or a
    ret
validate_response_id:
    ld hl,(FIELD_LENGTHS+10)
    ld de,8
    or a
    sbc hl,de
    jp nz,schema_fail
    ld hl,P_RESPONSE
    ld b,8
validate_id_loop:
    ld a,(hl)
    cp 48
    jp c,schema_fail
    cp 58
    jp c,validate_id_next
    cp 65
    jp c,schema_fail
    cp 71
    jp nc,schema_fail
validate_id_next:
    inc hl
    djnz validate_id_loop
    ld hl,P_RESPONSE
    ld de,zero_id
    call strings_equal
    jp z,schema_fail
    or a
    ret
schema_fail:
    ld a,3
    ld (last_error),a
    scf
    ret

pending_id: dw 0
next_id: dw 1
selected_id: dw 0
scan_id: dw 1
last_response_id: dw 0
storage_locked: db 0
draft_loaded: db 0
draft_problem: db 0
auto_enabled: db 1
auto_call: db 0
poll_tick: dw 0
command_note: dw 0
note_pointer: dw 0
extension_index: db 0
name_buffer: ds 11
old_name: ds 11
id_ascii: ds 9
extension_table: dm "ID REQRSPACKTMPAKTCANCNTRXT"
draft_name: dm "MSXDRAFTJSN"
backup_name: dm "MSXDRAFTBAK"
draft_tmp: dm "MSXDRAFTTMP"
note_restored: dm "[SD] Rascunho restaurado."
 db 0
note_pending: dm "[SD] Existe requisicao pendente. ID:"
 db 0
note_locked: dm "[SD] Metadados ambiguos/corrompidos. Fila bloqueada."
 db 0
note_saved: dm "[SD] Rascunho JSON gravado e conferido."
 db 0
note_file_error: dm "[SD] Falha de arquivo/validacao. Texto mantido."
 db 0
note_no_draft: dm "[SD] Sem rascunho valido. Editor mantido."
 db 0
note_queued: dm "[SD] Requisicao JSON publicada; aguardando .RSP. ID:"
 db 0
note_no_pending: dm "[SD] Nenhuma requisicao pendente."
 db 0
note_bad_response: dm "[SD] Resposta/ACK invalido ou erro de disco; auto OFF."
 db 0
note_wait: dm "[SD] .RSP ainda nao foi publicado."
 db 0
note_no_response: dm "[SD] Nenhuma resposta concluida para rever."
 db 0
note_review: dm "[SD] Revisao explicita; nao gera outro ACK."
 db 0
response_label: dm "[RESPOSTA / JSON LOCAL - LAN OU SD]"
 db 0
note_auto_off: dm "[AUTO] Consulta automatica OFF."
 db 0
note_auto_on: dm "[SD] Consulta automatica ON (600 ticks)."
 db 0

note_draft_problem: dm "[SD] Rascunho principal invalido; backup preservado."
 db 0

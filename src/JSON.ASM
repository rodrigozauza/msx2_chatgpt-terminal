; Strict local JSON object. Eight string fields, no nesting; incremental FCB input.
json_load:
 call dos_open
 ret c
 call json_parse
 push af
 call dos_close
 jp c,json_close_failed
 pop af
 ret
json_close_failed:
 pop af
 scf
 ret
json_parse:
 ld hl,META
 ld bc,256
 xor a
 call fill_memory
 xor a
 ld (MSG_BUFFER),a
 ld (REPLY_BUFFER),a
 ld (fields_seen),a
 call json_ws
 ret c
 cp 123
 jp nz,json_fail
json_next_field:
 call json_ws
 ret c
 cp 34
 jp nz,json_fail
 ld hl,KEY_BUFFER
 ld (string_dest),hl
 ld hl,31
 ld (string_limit),hl
 ld a,1
 ld (ascii_only),a
 call json_string
 ret c
 call json_find_field
 ret c
 ld (field_index),a
 ld b,a
 ld a,1
 inc b
json_field_bit:
 dec b
 jp z,json_bit_ready
 rlca
 jp json_field_bit
json_bit_ready:
 ld b,a
 ld a,(fields_seen)
 and b
 jp nz,json_fail
 ld a,(fields_seen)
 or b
 ld (fields_seen),a
 call json_ws
 ret c
 cp 58
 jp nz,json_fail
 call json_ws
 ret c
 cp 34
 jp nz,json_fail
 ld a,(field_index)
 ld l,a
 ld h,0
 ld e,a
 ld d,0
 add hl,hl
 add hl,hl
 add hl,de
 ld de,json_destinations
 add hl,de
 ld e,(hl)
 inc hl
 ld d,(hl)
 ld (string_dest),de
 inc hl
 ld e,(hl)
 inc hl
 ld d,(hl)
 ld (string_limit),de
 inc hl
 ld a,(hl)
 ld (ascii_only),a
 call json_string
 ret c
 ld a,(field_index)
 ld l,a
 ld h,0
 add hl,hl
 ld de,FIELD_LENGTHS
 add hl,de
 ld de,(string_length)
 ld (hl),e
 inc hl
 ld (hl),d
 call json_ws
 ret c
 cp 44
 jp z,json_next_field
 cp 125
 jp nz,json_fail
 ld a,(fields_seen)
 cp &FF
 jp nz,json_fail
json_trailing:
 call read_byte
 jp c,json_end_of_input
 call json_is_space
 jp z,json_trailing
 jp json_fail
json_end_of_input:
 ld a,(io_error)
 or a
 jp nz,dos_fail
 or a
 ret
json_ws:
 call read_byte
 jp c,json_fail
 call json_is_space
 jp z,json_ws
 ret
json_is_space:
 cp 32
 ret z
 cp 9
 ret z
 cp 10
 ret z
 cp 13
 ret
json_find_field:
 ld hl,json_key_pointers
 ld (key_table_ptr),hl
 xor a
 ld (key_index),a
json_key_loop:
 ld hl,(key_table_ptr)
 ld e,(hl)
 inc hl
 ld d,(hl)
 inc hl
 ld (key_table_ptr),hl
 ld hl,KEY_BUFFER
 call strings_equal
 jp z,json_key_found
 ld a,(key_index)
 inc a
 ld (key_index),a
 cp 8
 jp nz,json_key_loop
 jp json_fail
json_key_found:
 ld a,(key_index)
 or a
 ret
strings_equal:
 ld a,(de)
 cp (hl)
 ret nz
 or a
 ret z
 inc hl
 inc de
 jp strings_equal
json_string:
 ld hl,0
 ld (string_length),hl
json_string_loop:
 call read_byte
 jp c,json_fail
 cp 34
 jp z,json_string_end
 cp 92
 jp z,json_escape
 cp 32
 jp c,json_fail
 call json_utf8
 ret c
 jp json_store_codepoint
json_escape:
 call read_byte
 jp c,json_fail
 cp 34
 jp z,json_escape_ascii
 cp 92
 jp z,json_escape_ascii
 cp 47
 jp z,json_escape_ascii
 cp 110
 jp z,json_escape_n
 cp 114
 jp z,json_escape_r
 cp 116
 jp z,json_escape_t
 cp 98
 jp z,json_escape_b
 cp 102
 jp z,json_escape_f
 cp 117
 jp nz,json_fail
 call json_hex4
 ret c
 ld a,h
 cp &D8
 jp c,json_escape_bmp
 cp &DC
 jp c,json_high_surrogate
 cp &E0
 jp c,json_fail
json_escape_bmp:
 ld (codepoint_low),hl
 xor a
 ld (codepoint_high),a
 jp json_store_codepoint
json_high_surrogate:
 call read_byte
 jp c,json_fail
 cp 92
 jp nz,json_fail
 call read_byte
 jp c,json_fail
 cp 117
 jp nz,json_fail
 call json_hex4
 ret c
 ld a,h
 cp &DC
 jp c,json_fail
 cp &E0
 jp nc,json_fail
 ld a,1
 ld (codepoint_high),a
 ld hl,0
 ld (codepoint_low),hl
 jp json_store_codepoint
json_escape_n:
 ld a,10
 jp json_escape_ascii
json_escape_r:
 ld a,13
 jp json_escape_ascii
json_escape_t:
 ld a,9
 jp json_escape_ascii
json_escape_b:
 ld a,8
 jp json_escape_ascii
json_escape_f:
 ld a,12
json_escape_ascii:
 ld h,0
 ld l,a
 ld (codepoint_low),hl
 xor a
 ld (codepoint_high),a
json_store_codepoint:
 call unicode_to_msx
 ret c
 ld (decoded_byte),a
 ld hl,(string_length)
 ld de,(string_limit)
 or a
 sbc hl,de
 jp nc,json_limit_fail
 ld hl,(string_dest)
 ld de,(string_length)
 add hl,de
 ld a,(decoded_byte)
 ld (hl),a
 ld hl,(string_length)
 inc hl
 ld (string_length),hl
 jp json_string_loop
json_string_end:
 ld hl,(string_dest)
 ld de,(string_length)
 add hl,de
 ld (hl),0
 or a
 ret
json_hex4:
 ld hl,0
 ld b,4
json_hex_loop:
 call read_byte
 jp c,json_fail
 call json_hex_digit
 ret c
 add hl,hl
 add hl,hl
 add hl,hl
 add hl,hl
 or l
 ld l,a
 djnz json_hex_loop
 or a
 ret
json_hex_digit:
 cp 48
 jp c,json_fail
 cp 58
 jp c,json_hex_number
 cp 65
 jp c,json_fail
 cp 71
 jp c,json_hex_upper
 cp 97
 jp c,json_fail
 cp 103
 jp nc,json_fail
 sub 87
 or a
 ret
json_hex_upper:
 sub 55
 or a
 ret
json_hex_number:
 sub 48
 or a
 ret

json_utf8:
 ld h,0
 ld l,a
 ld (codepoint_low),hl
 xor a
 ld (codepoint_high),a
 ld a,l
 cp &80
 jp c,utf8_valid
 cp &C2
 jp c,json_utf8_fail
 cp &E0
 jp c,utf8_two
 cp &F0
 jp c,utf8_three
 cp &F5
 jp nc,json_utf8_fail
 and 7
 ld b,3
 jp utf8_init
utf8_three:
 and 15
 ld b,2
 jp utf8_init
utf8_two:
 and 31
 ld b,1
utf8_init:
 ld h,0
 ld l,a
 ld (codepoint_low),hl
 ld a,b
 ld (utf8_left),a
 ld (utf8_total),a
utf8_continuation:
 call read_byte
 jp c,json_utf8_fail
 ld c,a
 and &C0
 cp &80
 jp nz,json_utf8_fail
 ld a,c
 and 63
 ld (utf8_bits),a
 ld hl,(codepoint_low)
 ld b,6
utf8_shift:
 add hl,hl
 ld a,(codepoint_high)
 rla
 ld (codepoint_high),a
 djnz utf8_shift
 ld a,(utf8_bits)
 or l
 ld l,a
 ld (codepoint_low),hl
 ld a,(utf8_left)
 dec a
 ld (utf8_left),a
 jp nz,utf8_continuation
 ld a,(utf8_total)
 cp 3
 jp z,utf8_validate_four
 cp 2
 jp nz,utf8_validate_bmp
 ld a,h
 cp 8
 jp c,json_utf8_fail
utf8_validate_bmp:
 ld a,h
 cp &D8
 jp c,utf8_valid
 cp &E0
 jp c,json_utf8_fail
utf8_valid:
 or a
 ret
utf8_validate_four:
 ld a,(codepoint_high)
 or a
 jp z,json_utf8_fail
 cp &11
 jp nc,json_utf8_fail
 or a
 ret

unicode_to_msx:
 ld a,(ascii_only)
 or a
 jp z,unicode_text
 ld a,(codepoint_high)
 or a
 jp nz,json_fail
 ld hl,(codepoint_low)
 ld a,h
 or a
 jp nz,json_fail
 ld a,l
 cp 32
 jp c,json_fail
 cp 127
 jp nc,json_fail
 or a
 ret
unicode_text:
 ld a,(codepoint_high)
 or a
 jp nz,unicode_unknown
 ld hl,(codepoint_low)
 ld a,h
 or a
 jp nz,unicode_extended
 ld a,l
 cp 10
 ret z
 or a
 jp z,unicode_unknown
 cp 32
 jp c,unicode_space
 cp 127
 jp c,unicode_ascii_ok
unicode_extended:
 ld a,h
 cp &E0
 jp nz,unicode_lookup
 ld a,l
 cp &80
 ret nc
unicode_lookup:
 ld hl,unicode_table
unicode_reverse_loop:
 ld a,(hl)
 or a
 jp z,unicode_unknown
 ld (unicode_candidate),a
 inc hl
 ld a,(codepoint_low)
 cp (hl)
 inc hl
 jp nz,unicode_reverse_next
 ld a,(codepoint_low+1)
 cp (hl)
 jp z,unicode_reverse_found
unicode_reverse_next:
 inc hl
 jp unicode_reverse_loop
unicode_reverse_found:
 ld a,(unicode_candidate)
unicode_ascii_ok:
 or a
 ret
unicode_space:
 ld a,32
 or a
 ret
unicode_unknown:
 ld a,63
 or a
 ret
msx_to_unicode:
 ld (unicode_candidate),a
 ld hl,unicode_table
unicode_forward_loop:
 ld a,(hl)
 or a
 jp z,unicode_private
 ld b,a
 ld a,(unicode_candidate)
 cp b
 jp z,unicode_forward_found
 inc hl
 inc hl
 inc hl
 jp unicode_forward_loop
unicode_forward_found:
 inc hl
 ld e,(hl)
 inc hl
 ld d,(hl)
 ex de,hl
 ret
unicode_private:
 ld h,&E0
 ld a,(unicode_candidate)
 ld l,a
 ret
json_fail:
 ld a,2
 ld (last_error),a
 scf
 ret
json_utf8_fail:
 ld a,5
 ld (last_error),a
 scf
 ret
json_limit_fail:
 ld a,4
 ld (last_error),a
 scf
 ret

json_write:
 call dos_create
 ret c
 call json_generate
 jp c,json_write_failed
 jp writer_finish
json_write_failed:
 call dos_close
 scf
 ret
emit_z:
 ld a,(hl)
 or a
 ret z
 call write_byte
 ret c
 inc hl
 jp emit_z
emit_string:
 ld a,34
 call write_byte
 ret c
emit_string_loop:
 ld a,(hl)
 or a
 jp z,emit_string_end
 push hl
 call emit_character
 pop hl
 ret c
 inc hl
 jp emit_string_loop
emit_string_end:
 ld a,34
 jp write_byte
emit_character:
 cp 34
 jp z,emit_escaped
 cp 92
 jp z,emit_escaped
 cp 32
 jp c,emit_control
 cp 127
 jp c,write_byte
 call msx_to_unicode
 jp emit_unicode
emit_control:
 ld h,0
 ld l,a
 jp emit_unicode
emit_escaped:
 ld (escaped_byte),a
 ld a,92
 call write_byte
 ret c
 ld a,(escaped_byte)
 jp write_byte
emit_unicode:
 ex de,hl
 ld hl,HEX_BUFFER
 call hex_at
 ld (hl),0
 ld a,92
 call write_byte
 ret c
 ld a,117
 call write_byte
 ret c
 ld hl,HEX_BUFFER
 jp emit_z
json_generate:
 ld hl,json_head
 call emit_z
 ret c
 ld hl,(out_request)
 call emit_string
 ret c
 ld hl,json_conversation
 call emit_z
 ret c
 ld hl,conversation_value
 call emit_string
 ret c
 ld hl,json_state
 call emit_z
 ret c
 ld hl,(out_state)
 call emit_string
 ret c
 ld hl,json_message
 call emit_z
 ret c
 ld hl,(out_message)
 call emit_string
 ret c
 ld hl,json_response
 call emit_z
 ret c
 ld hl,(out_response)
 call emit_string
 ret c
 ld hl,json_reply
 call emit_z
 ret c
 ld hl,(out_reply)
 call emit_string
 ret c
 ld hl,json_error
 call emit_z
 ret c
 ld hl,(out_error)
 call emit_string
 ret c
 ld a,125
 call write_byte
 ret c
 ld a,13
 call write_byte
 ret c
 ld a,10
 jp write_byte
fields_seen: db 0
field_index: db 0
key_index: db 0
key_table_ptr: dw 0
string_dest: dw 0
string_limit: dw 0
string_length: dw 0
ascii_only: db 0
decoded_byte: db 0
codepoint_low: dw 0
codepoint_high: db 0
utf8_left: db 0
utf8_total: db 0
utf8_bits: db 0
unicode_candidate: db 0
escaped_byte: db 0
out_request: dw 0
out_state: dw 0
out_message: dw 0
out_response: dw 0
out_reply: dw 0
out_error: dw 0
json_destinations:
 dw P_PROTOCOL,15
 db 1
 dw P_REQUEST,8
 db 1
 dw P_CONVERSATION,8
 db 1
 dw P_STATE,15
 db 1
 dw MSG_BUFFER,2047
 db 0
 dw P_RESPONSE,8
 db 1
 dw REPLY_BUFFER,2047
 db 0
 dw P_ERROR,31
 db 1
json_key_pointers:
 dw key_protocol,key_request,key_conversation,key_state
 dw key_message,key_response,key_reply,key_error
key_protocol: db 112,114,111,116,111,99,111,108,0
key_request: db 114,101,113,117,101,115,116,95,105,100,0
key_conversation: db 99,111,110,118,101,114,115,97,116,105,111,110,95,105,100,0
key_state: db 115,116,97,116,101,0
key_message: db 109,101,115,115,97,103,101,0
key_response: db 114,101,115,112,111,110,115,101,95,105,100,0
key_reply: db 114,101,112,108,121,0
key_error: db 101,114,114,111,114,95,99,111,100,101,0
json_head: db 123,34,112,114,111,116,111,99,111,108,34,58,34,109,115,120,99,104,97,116,47,49,34,44,34,114,101,113,117,101,115,116,95,105,100,34,58,0
json_conversation: db 44,34,99,111,110,118,101,114,115,97,116,105,111,110,95,105,100,34,58,0
json_state: db 44,34,115,116,97,116,101,34,58,0
json_message: db 44,34,109,101,115,115,97,103,101,34,58,0
json_response: db 44,34,114,101,115,112,111,110,115,101,95,105,100,34,58,0
json_reply: db 44,34,114,101,112,108,121,34,58,0
json_error: db 44,34,101,114,114,111,114,95,99,111,100,101,34,58,0
protocol_value: db 109,115,120,99,104,97,116,47,49,0
conversation_value: db 48,48,48,48,48,48,48,49,0
zero_id: db 48,48,48,48,48,48,48,48,0
empty_value: db 0
state_draft: db 100,114,97,102,116,0
state_pending: db 112,101,110,100,105,110,103,0
state_completed: db 99,111,109,112,108,101,116,101,100,0
state_error: db 101,114,114,111,114,0
state_ack: db 97,99,107,0

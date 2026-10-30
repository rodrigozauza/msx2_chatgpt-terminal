; UNAPI.ASM -- discovery/call wrapper reused from homologated TCPTEST.
EXTBIO: equ &FFCA
ARG: equ &F847
HOKVLD: equ &FB20
net_init:
    ld hl,ARG
    ld de,net_saved_arg
    ld bc,16
    ldir
    ld a,1
    ld (net_arg_saved),a
    ld a,(HOKVLD)
    and 1
    ret z
    ld a,1
    ld (net_ext_ready),a
    ld hl,0
    ld a,&FF
    ld de,&2222
    call EXTBIO
    cp 3
    ret c
    ld a,h
    cp &C0
    ret c
    ld (net_helper_ptr),hl
    ld (net_helper_call+1),hl
    ld a,h
    or l
    ret z
    ret
net_copy_id:
    ld hl,(net_api_id)
    ld de,ARG
net_copy_id_loop:
    ld a,(hl)
    ld (de),a
    inc hl
    inc de
    or a
    jp nz,net_copy_id_loop
    ret
net_count_api:
    call net_copy_id
    xor a
    ld b,0
    ld de,&2222
    call EXTBIO
    ld a,b
    ld (net_api_count),a
    ret
; net_api_index selects implementation. Carry = RAM implementation without helper
; or malformed entry outside page 1/page 3.
net_select_api:
    call net_copy_id
    ld a,(net_api_index)
    ld de,&2222
    call EXTBIO
    ld (net_api_slot),a
    ld a,b
    ld (net_api_seg),a
    ld (net_api_entry),hl
    ld a,h
    cp &C0
    jp nc,net_select_direct
    cp &40
    jp c,net_select_fail
    cp &80
    jp nc,net_select_fail
    ld a,(net_api_seg)
    cp &FF
    jp z,net_select_rom
    ld hl,(net_helper_ptr)
    ld a,h
    or l
    jp z,net_select_fail
    ld a,2
    ld (net_api_type),a
    or a
    ret
net_select_rom:
    ld a,1
    ld (net_api_type),a
    or a
    ret
net_select_direct:
    ld (net_direct_call+1),hl
    xor a
    ld (net_api_type),a
    ret
net_select_fail:
    scf
    ret

; Preserves incoming function number A and all API parameter registers.
; CALSLT/helper restore page 1. EI follows ROM BIOS calls (DOS enters with EI).
net_call_api:
    push af
    ld a,(net_api_type)
    or a
    jp z,net_call_direct
    cp 1
    jp z,net_call_rom
    pop af
    ld ix,(net_api_entry)
    ld iy,(net_api_seg)
net_helper_call:
    jp 0
net_call_rom:
    pop af
    ld ix,(net_api_entry)
    ld iy,(net_api_seg)
    call &001C
    ei
    ret
net_call_direct:
    pop af
net_direct_call:
    jp 0


net_helper_ptr: dw 0
net_api_entry: dw 0
net_api_seg: db &FF
net_api_slot: db 0
net_api_type: db 0
net_api_count: db 0
net_api_index: db 1
net_api_id: dw 0
net_impl_version: dw 0
net_spec_version: dw 0
net_name_ptr: dw 0
net_arg_saved: db 0
net_ext_ready: db 0
net_start_tick: dw 0
net_saved_arg: ds 16
net_id_tcp: dm "TCP/IP"
    db 0

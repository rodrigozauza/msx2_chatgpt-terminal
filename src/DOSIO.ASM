; DOSIO.ASM -- MSX-DOS 1 FCB calls only; source DOS2-FCS sections 3.14..3.34.
; One FCB at a time, one-byte records, bounded 256-byte transfers.
; All routines return carry on failure. No handle APIs or DOS2 error services.
dos_fcb:
    ld (name_pointer),hl
    ld hl,FCB
    ld bc,37
    xor a
    call fill_memory
    ld hl,(name_pointer)
    ld de,FCB+1
    ld bc,11
    ldir
    ret
dos_open:
    call dos_fcb
    ld de,FCB
    ld c,&0F
    call BDOS
    or a
    jp nz,dos_fail
    ld a,1
    ld (file_open),a
    ld (FCB+14),a
    xor a
    ld (FCB+15),a
    ld (io_error),a
    ld hl,0
    ld (read_count),hl
    ld (write_count),hl
    ; Reject files above 32767 bytes before any read.
    ld hl,(FCB+18)
    ld a,h
    or l
    jp nz,dos_open_bad
    ld hl,(FCB+16)
    bit 7,h
    jp nz,dos_open_bad
    ld (file_remaining),hl
    or a
    ret
dos_open_bad:
    call dos_close
    ld a,4
    ld (last_error),a
    scf
    ret
dos_create:
    call dos_fcb
    ld de,FCB
    ld c,&16
    call BDOS
    or a
    jp nz,dos_fail
    ld a,1
    ld (file_open),a
    ld (FCB+14),a
    xor a
    ld (FCB+15),a
    ld (io_error),a
    ld hl,0
    ld (write_count),hl
    ld (read_count),hl
    or a
    ret
dos_close:
    ld a,(file_open)
    or a
    ret z
    ld de,FCB
    ld c,&10
    call BDOS
    or a
    jp nz,dos_fail
    xor a
    ld (file_open),a
    ret
dos_dta:
    ld de,IOBUF
    ld c,&1A
    jp BDOS
dos_reset_dta:
    ld de,&0080
    ld c,&1A
    jp BDOS
dos_sync:
    ; DSKRST explicitly flushes disk buffers and resets DTA to 80h.
    ld c,&0D
    jp BDOS
dos_exists:
    call dos_fcb
    ld de,FCB
    ld c,&0F
    call BDOS
    or a
    jp nz,dos_absent
    ld de,FCB
    ld c,&10
    call BDOS
    or a
    jp nz,dos_fail
    or a
    ret
dos_absent:
    scf
    ret
dos_delete:
    call dos_fcb
    ld de,FCB
    ld c,&13
    call BDOS
    or a
    jp nz,dos_fail
    call dos_sync
    or a
    ret
; HL=old FCB name (11 bytes), DE=new name (11 bytes).
dos_rename:
    ld (rename_pointer),de
    call dos_fcb
    ld hl,(rename_pointer)
    ld de,FCB+17
    ld bc,11
    ldir
    ld de,FCB
    ld c,&17
    call BDOS
    or a
    jp nz,dos_fail
    call dos_sync
    or a
    ret
dos_fail:
    ld a,1
    ld (last_error),a
    ld (io_error),a
    scf
    ret

; Returns A=next byte, CF=EOF/error. BC/DE/HL preserved.
read_byte:
    push bc
    push de
    push hl
    ld hl,(read_count)
    ld a,h
    or l
    jp nz,read_buffered
    ld hl,(file_remaining)
    ld a,h
    or l
    jp z,read_eof
    ld de,256
    or a
    sbc hl,de
    jp nc,read_full_block
    ld hl,(file_remaining)
    jp read_block
read_full_block:
    ld hl,256
read_block:
    ld (read_requested),hl
    call dos_dta
    ld hl,(read_requested)
    ld de,FCB
    ld c,&27
    call BDOS
    or a
    jp nz,read_failure
    ld de,(read_requested)
    or a
    sbc hl,de
    jp nz,read_failure
    ld hl,(file_remaining)
    ld de,(read_requested)
    or a
    sbc hl,de
    ld (file_remaining),hl
    ld hl,(read_requested)
    ld (read_count),hl
    ld hl,IOBUF
    ld (read_pointer),hl
read_buffered:
    ld hl,(read_count)
    dec hl
    ld (read_count),hl
    ld hl,(read_pointer)
    ld a,(hl)
    inc hl
    ld (read_pointer),hl
    or a
    jp read_return
read_failure:
    call dos_fail
    jp read_return
read_eof:
    scf
read_return:
    pop hl
    pop de
    pop bc
    ret

; Writes A to buffered output. BC/DE/HL preserved; carry reports any flush error.
write_byte:
    push hl
    push de
    push bc
    ld (write_value),a
    ld hl,(write_count)
    ld de,IOBUF
    add hl,de
    ld a,(write_value)
    ld (hl),a
    ld hl,(write_count)
    inc hl
    ld (write_count),hl
    ld de,256
    or a
    sbc hl,de
    jp nz,write_no_flush
    call write_flush
    jp write_byte_done
write_no_flush:
    or a
write_byte_done:
    pop bc
    pop de
    pop hl
    ret
write_flush:
    ld a,(io_error)
    or a
    jp nz,dos_fail
    ld hl,(write_count)
    ld a,h
    or l
    ret z
    call dos_dta
    ld hl,(write_count)
    ld de,FCB
    ld c,&26
    call BDOS
    or a
    jp nz,dos_fail
    ld hl,0
    ld (write_count),hl
    or a
    ret
writer_finish:
    call write_flush
    jp c,writer_failed
    jp dos_close
writer_failed:
    call dos_close
    scf
    ret

name_pointer: dw 0
rename_pointer: dw 0
file_open: db 0
io_error: db 0
last_error: db 0
file_remaining: dw 0
read_count: dw 0
read_requested: dw 0
read_pointer: dw 0
write_count: dw 0
write_value: db 0

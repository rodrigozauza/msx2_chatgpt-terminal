; SCREEN7.ASM -- V9938 bitmap, page 0, 512x212, 80x24 cells, 6x8 pixels each, 16-pixel margins.
; BIOS config/upload plus interrupt-safe V9938 commands through BIOS-derived ports.
bios_call:
    ld iy,(EXPTBL-1)
    call CALSLT
    ei
    ret
screen_enter:
    ld hl,RG0SAV
    ld de,saved_regs
    ld bc,8
    ldir
    ld hl,&FFE7
    ld bc,16
    ldir
    ld a,(SCRMOD)
    ld (saved_mode),a
    ld a,(CNSDFG)
    ld (saved_cnsdfg),a
    ld a,1
    ld (CNSDFG),a
    ld a,(&FAF6)
    ld (saved_acpage),a
    xor a
    ld (&FAF6),a
    call vdp_init_ports
    ld b,&20
    ld c,1
    call screen_reg
    ; In SCREEN 5, addresses are linear. Stash all physical DOS 16K at
    ; 1C000h..1FFFFh using HMMM; this area is outside SCREEN 7 + font atlas.
    ld a,5
    ld (SCRMOD),a
    ld b,6
    ld c,0
    call screen_reg
    ld b,&0A
    ld c,8
    call screen_reg
    ld hl,save_dos_command
    call vdp_command
    call vdp_wait
    ld a,1
    ld (video_saved),a
    ld a,7
    ld (SCRMOD),a
    ; Select Graphic 6, display page 0; preserve palette and PAL/NTSC.
    ld b,&0A
    ld c,0
    call screen_reg
    ld b,&1F
    ld c,2
    call screen_reg
    ld b,1
    ld c,7
    call screen_reg
    ld b,&0A
    ld c,8
    call screen_reg
    ld a,(saved_regs+9)
    and &02
    or &80
    ld b,a
    ld c,9
    call screen_reg
    ld b,0
    ld c,14
    call screen_reg
    ld b,0
    ld c,23
    call screen_reg
    call build_font_atlas
    ; Clear bottom 20 scanlines. ROWBUF remains a single scanline.
    ld hl,ROWBUF
    ld bc,256
    ld a,&11
    call fill_memory
    ld a,192
    ld (render_y),a
screen_bottom:
    call render_send
    ld a,(render_y)
    inc a
    ld (render_y),a
    cp 212
    jp nz,screen_bottom
    call mark_all
    call render_dirty
    ld b,&60
    ld c,1
screen_reg:
    ld ix,&0047
    jp bios_call
screen_leave:
    ld a,(video_saved)
    or a
    ret z
    ld b,&20
    ld c,1
    call screen_reg
    ; Restore physical DOS data in the SAME linear mapping used to save it.
    ld a,5
    ld (SCRMOD),a
    ld b,6
    ld c,0
    call screen_reg
    ld hl,restore_dos_command
    call vdp_command
    call vdp_wait
    call screen_restore_regs
    jp screen_restore_state
screen_restore_regs:
    xor a
    ld (register_index),a
screen_restore_reg:
    ld a,(register_index)
    cp 1
    jp z,screen_restore_next
    ld e,a
    ld d,0
    ld hl,saved_regs
    add hl,de
    ld b,(hl)
    ld c,a
    call screen_reg
screen_restore_next:
    ld a,(register_index)
    inc a
    ld (register_index),a
    cp 24
    jp nz,screen_restore_reg
    ret
screen_restore_state:
    ld a,(saved_mode)
    ld (SCRMOD),a
    ld a,(saved_cnsdfg)
    ld (CNSDFG),a
    ld a,(saved_acpage)
    ld (&FAF6),a
    ld a,(saved_regs+1)
    ld b,a
    ld c,1
    call screen_reg
    xor a
    ld (video_saved),a
    ret
; A=row. Pattern+color invalidation. Preserves main registers.
mark_row:
    push af
    push hl
    push de
    ld e,a
    ld d,0
    ld hl,DIRTY
    add hl,de
    ld a,(hl)
    or 3
    ld (hl),a
    pop de
    pop hl
    pop af
    ret
mark_cursor_row:
    ld a,(cursor_screen_row)
mark_pattern_row:
    push af
    push hl
    push de
    ld e,a
    ld d,0
    ld hl,DIRTY
    add hl,de
    ld a,(hl)
    or 1
    ld (hl),a
    pop de
    pop hl
    pop af
    ret
mark_all:
    ld hl,DIRTY
    ld bc,TEXT_ROWS
    ld a,3
    jp fill_memory

; Fill BC bytes at HL with A, including safe zero/one-byte handling.
fill_memory:
    ld (fill_value),a
    ld a,b
    or c
    ret z
    ld a,(fill_value)
    ld (hl),a
    dec bc
    ld a,b
    or c
    ret z
    ld d,h
    ld e,l
    inc de
    ldir
    ret

; A=row -> HL=GRID+row*80; destroys DE.
grid_row_address:
    ld h,0
    ld l,a
    call grid_row_offset
    ld de,GRID
    add hl,de
    ret
; HL=row -> HL=row*80, used by editor/history after bounds checks.
grid_row_offset:
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    ld d,h
    ld e,l
    add hl,hl
    add hl,hl
    add hl,de
    ret
glyph_address:
    ld h,0
    ld l,a
    add hl,hl
    add hl,hl
    add hl,hl
    ld de,font8x8
    add hl,de
    ret


render_dirty:
    xor a
    ld (render_row),a
render_next_row:
    ld a,(render_row)
    ld e,a
    ld d,0
    ld hl,DIRTY
    add hl,de
    ld a,(hl)
    or a
    call nz,render_patterns
    ld a,(render_row)
    ld e,a
    ld d,0
    ld hl,DIRTY
    add hl,de
    ld (hl),0
    ld a,(render_row)
    inc a
    ld (render_row),a
    cp TEXT_ROWS
    jp nz,render_next_row
    ret
render_patterns:
    ld a,255
    ld (render_cursor_col),a
    ld a,(cursor_phase)
    or a
    jr z,render_cursor_ready
    ld a,(cursor_screen_row)
    ld b,a
    ld a,(render_row)
    cp b
    jr nz,render_cursor_ready
    ld a,(cursor_col)
    ld (render_cursor_col),a
render_cursor_ready:
    call render_bounds
    ld a,(render_first)
    cp COLUMNS
    ret z
    ld a,(render_row)
    ld e,a
    ld d,0
    ld hl,ROWCOLORS
    add hl,de
    ld a,(hl)
    ld (render_color),a
    ld hl,atlas_colors
    ld de,atlas_x
    ld b,5
render_palette:
    cp (hl)
    jr z,render_palette_found
    inc hl
    inc de
    inc de
    djnz render_palette
    ld de,atlas_x+2
render_palette_found:
    ex de,hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (atlas_base_x),de
    ld a,(render_full)
    or a
    call nz,vdp_fill_row
    ld a,(render_row)
    call grid_row_address
    ld (render_grid_ptr),hl
    xor a
    ld (render_col),a
render_character:
    ld a,(render_full)
    or a
    jr nz,render_cell_changed
    ld a,(render_col)
    ld e,a
    ld d,0
    ld hl,CHANGED_CELLS
    add hl,de
    ld a,(hl)
    or a
    jr z,render_cell_next
render_cell_changed:
    ld hl,(render_grid_ptr)
    ld a,(hl)
    ld b,a
    and 15
    ld l,a
    ld h,0
    add hl,hl
    ld d,h
    ld e,l
    add hl,hl
    add hl,de
    ld de,(atlas_base_x)
    add hl,de
    ld (cell_command),hl
    ld a,b
    and &F0
    rrca
    ld l,a
    ld h,1
    ld (cell_command+2),hl
    ld a,(render_col)
    ld l,a
    ld h,0
    add hl,hl
    ld d,h
    ld e,l
    add hl,hl
    add hl,de
    ld de,16
    add hl,de
    ld (cell_command+4),hl
    ld (cursor_command+4),hl
    ld a,(render_row)
    add a,a
    add a,a
    add a,a
    ld l,a
    ld h,0
    ld (cell_command+6),hl
    ld (cursor_command+6),hl
    ld hl,cell_command
    call vdp_command
    ld a,(render_cursor_col)
    ld b,a
    ld a,(render_col)
    cp b
    jr nz,render_cell_next
    ld a,(render_color)
    ld b,a
    rrca
    rrca
    rrca
    rrca
    xor b
    and 15
    ld (cursor_command+12),a
    ld hl,cursor_command
    call vdp_command
render_cell_next:
    ld hl,(render_grid_ptr)
    inc hl
    ld (render_grid_ptr),hl
    ld a,(render_col)
    inc a
    ld (render_col),a
    cp COLUMNS
    jp nz,render_character
    jp vdp_wait
vdp_fill_row:
    ld a,(render_row)
    add a,a
    add a,a
    add a,a
    ld l,a
    ld h,0
    ld (fill_command+6),hl
    ld a,(render_color)
    and 15
    ld b,a
    rlca
    rlca
    rlca
    rlca
    or b
    ld (fill_command+12),a
    ld hl,fill_command
    jp vdp_command
; Find changed span; cache character AND cursor inversion separately.
render_bounds:
    xor a
    ld (render_first),a
    ld a,79
    ld (render_last),a
    ld a,1
    ld (render_full),a
    ld a,(render_row)
    cp STATUS_ROW
    ret c
    cp INPUT_ROW+INPUT_ROWS
    ret nc
    sub STATUS_ROW
    ld e,a
    ld d,0
    ld hl,CACHE_COLORS
    add hl,de
    push hl
    ld hl,ROWCOLORS+STATUS_ROW
    add hl,de
    ld a,(hl)
    pop hl
    cp (hl)
    ld (hl),a
    jr nz,render_cache_full
    ld a,(render_row)
    ld e,a
    ld d,0
    ld hl,DIRTY
    add hl,de
    bit 1,(hl)
    jr nz,render_cache_full
    xor a
    ld (render_full),a
    ld a,80
    ld (render_first),a
render_cache_full:
    ld hl,CHANGED_CELLS
    ld bc,80
    xor a
    call fill_memory
    ld a,(render_row)
    sub STATUS_ROW
    ld l,a
    ld h,0
    call grid_row_offset
    ld de,RENDER_CACHE
    add hl,de
    ld (cache_pointer),hl
    ld de,320
    add hl,de
    ld (cursor_cache_pointer),hl
    ld a,(render_row)
    call grid_row_address
    ld (render_grid_ptr),hl
    xor a
    ld (render_col),a
render_cache_loop:
    ld hl,(render_grid_ptr)
    ld a,(hl)
    inc hl
    ld (render_grid_ptr),hl
    ld hl,(cache_pointer)
    cp (hl)
    ld (hl),a
    inc hl
    ld (cache_pointer),hl
    call nz,render_changed
    ld a,(render_cursor_col)
    ld b,a
    ld a,(render_col)
    cp b
    ld a,0
    jr nz,render_cache_cursor
    inc a
render_cache_cursor:
    ld hl,(cursor_cache_pointer)
    cp (hl)
    ld (hl),a
    inc hl
    ld (cursor_cache_pointer),hl
    call nz,render_changed
    ld a,(render_col)
    inc a
    ld (render_col),a
    cp COLUMNS
    jp nz,render_cache_loop
    ret
render_changed:
    ld a,(render_col)
    ld e,a
    ld d,0
    ld hl,CHANGED_CELLS
    add hl,de
    ld (hl),1
    ld a,(render_col)
    ld b,a
    ld a,(render_first)
    cp b
    jr c,render_changed_last
    ld a,b
    ld (render_first),a
render_changed_last:
    ld a,(render_full)
    or a
    ret nz
    ld a,b
    ld (render_last),a
    ret
; 64 patterns x 3 bytes for the active foreground/background pair.
render_lookup:
    ld b,a
    ld a,(lookup_valid)
    or a
    jr z,render_build_lookup
    ld a,(lookup_color)
    cp b
    ret z
render_build_lookup:
    ld a,b
    ld (lookup_color),a
    ld (PAIR_TABLE+2),a
    and 15
    ld c,a
    rlca
    rlca
    rlca
    rlca
    or c
    ld (bg_pair),a
    ld (PAIR_TABLE),a
    ld a,b
    and &F0
    ld c,a
    rrca
    rrca
    rrca
    rrca
    or c
    ld (PAIR_TABLE+3),a
    ld a,b
    rlca
    rlca
    rlca
    rlca
    ld (PAIR_TABLE+1),a
    ld c,0
render_lookup_loop:
    ld a,c
    rlca
    rlca
    and 3
    or &F0
    ld l,a
    ld h,&57
    ld a,(hl)
    ld l,c
    ld h,&61
    ld (hl),a
    ld a,c
    rlca
    rlca
    rlca
    rlca
    and 3
    or &F0
    ld l,a
    ld h,&57
    ld a,(hl)
    ld l,c
    ld h,&62
    ld (hl),a
    ld a,c
    rrca
    rrca
    and 3
    or &F0
    ld l,a
    ld h,&57
    ld a,(hl)
    ld l,c
    ld h,&63
    ld (hl),a
    ld a,c
    add a,4
    ld c,a
    jp nc,render_lookup_loop
    ld a,1
    ld (lookup_valid),a
    ret
render_send:
    ld a,(render_y)
    ld d,a
    ld e,0
    ld hl,ROWBUF
    ld bc,256
    ld ix,&005C
    jp bios_call
saved_regs: ds 24
saved_mode: db 0
saved_cnsdfg: db 0
saved_acpage: db 0
video_saved: db 0
register_index: db 0
render_row: db 0
render_scan: db 0
render_col: db 0
render_y: db 0
render_grid_ptr: dw 0
render_buffer_ptr: dw 0
render_cursor_col: db 255
render_first: db 0
render_last: db 79
render_full: db 1
render_color: db 0
cache_pointer: dw 0
cursor_cache_pointer: dw 0
lookup_color: db 0
lookup_valid: db 0
bg_pair: db 0
fill_value: db 0

; Ports are taken from MAIN-ROM, not hard-coded to a cartridge/VDP model.
vdp_init_ports:
    ld a,(EXPTBL)
    ld hl,6
    call &000C
    ei
    inc a
    ld (vdp_status_port),a
    ld a,(EXPTBL)
    ld hl,7
    call &000C
    ei
    inc a
    ld (vdp_control_port),a
    add a,2
    ld (vdp_indirect_port),a
    ret
; Select S#2 atomically; always reset S#0 before allowing BIOS interrupts.
vdp_wait:
    push bc
vdp_wait_loop:
    di
    ld a,(vdp_control_port)
    ld c,a
    ld a,2
    out (c),a
    ld a,&8F
    out (c),a
    ld a,(vdp_status_port)
    ld c,a
    in a,(c)
    and 1
    ld b,a
    ld a,(vdp_control_port)
    ld c,a
    xor a
    out (c),a
    ld a,&8F
    out (c),a
    ei
    ld a,b
    or a
    jp nz,vdp_wait_loop
    pop bc
    ret
; HL points to R#32..R#46 (15 bytes). Command parameters streamed via port 3.
vdp_command:
    call vdp_wait
    di
    ld a,(vdp_control_port)
    ld c,a
    ld a,32
    out (c),a
    ld a,&91
    out (c),a
    ld a,(vdp_indirect_port)
    ld c,a
    ld b,15
vdp_command_byte:
    outi
    jp nz,vdp_command_byte
    ei
    ret
; Color atlases occupy SCREEN 7 page 1, Y=256..383, X=16..495.
; DOS stash occupies PHYSICAL 1C000h..1FFFFh; the two never overlap.
build_font_atlas:
    ld a,(atlas_ready)
    or a
    ret nz
    ld a,1
    ld (&FAF6),a
    xor a
    ld (atlas_scanline),a
atlas_scanline_loop:
    ld hl,ROWBUF
    ld bc,256
    ld a,17
    call fill_memory
    ld hl,ROWBUF+8
    ld (render_buffer_ptr),hl
    xor a
    ld (atlas_col),a
atlas_glyph_loop:
    ld a,(atlas_col)
    rrca
    rrca
    rrca
    rrca
    and 7
    ld e,a
    ld d,0
    ld hl,atlas_colors
    add hl,de
    ld a,(hl)
    call render_lookup
    ld a,(atlas_scanline)
    and &78
    add a,a
    ld b,a
    ld a,(atlas_col)
    and 15
    or b
    call glyph_address
    ld a,(atlas_scanline)
    and 7
    ld e,a
    ld d,0
    add hl,de
    ld a,(hl)
    and 252
    ld l,a
    ld h,&61
    ld de,(render_buffer_ptr)
    ld a,(hl)
    ld (de),a
    inc de
    inc h
    ld a,(hl)
    ld (de),a
    inc de
    inc h
    ld a,(hl)
    ld (de),a
    inc de
    ld (render_buffer_ptr),de
    ld a,(atlas_col)
    inc a
    ld (atlas_col),a
    cp 80
    jp nz,atlas_glyph_loop
    ld a,(atlas_scanline)
    ld d,a
    ld e,0
    ld hl,ROWBUF
    ld bc,256
    ld ix,&005C
    call bios_call
    ld a,(atlas_scanline)
    inc a
    ld (atlas_scanline),a
    cp 128
    jp nz,atlas_scanline_loop
    xor a
    ld (&FAF6),a
    inc a
    ld (atlas_ready),a
    ret
vdp_status_port: db &99
vdp_control_port: db &99
vdp_indirect_port: db &9B
atlas_ready: db 0
atlas_scanline: db 0
atlas_col: db 0
atlas_base_x: dw 0
atlas_colors: db &F4,&F1,&B1,&71,&81
atlas_x: dw 16,112,208,304,400
save_dos_command: dw 0,0,0,896,256,128
    db 0,0,&D0
restore_dos_command: dw 0,896,0,0,256,128
    db 0,0,&D0
cell_command: dw 0,0,0,0,6,8
    db 0,0,&D0
cursor_command: dw 0,0,0,0,6,8
    db 14,0,&83
fill_command: dw 0,0,0,0,512,8
    db 17,0,&C0

; Editor scroll is a VDP rectangle copy, not a redraw of 240 glyphs.
; Shift the cache with the same operation so only edge/cursor cells change.
vdp_scroll_editor:
    ld hl,scroll_command
    call vdp_command
    ld hl,clear_editor_command
    call vdp_command
    call vdp_wait
    ld hl,RENDER_CACHE+160
    ld de,RENDER_CACHE+80
    ld bc,160
    ldir
    ld hl,CURSOR_CACHE+160
    ld de,CURSOR_CACHE+80
    ld bc,160
    ldir
    ld hl,RENDER_CACHE+240
    ld bc,80
    ld a,32
    call fill_memory
    ld hl,CURSOR_CACHE+240
    ld bc,80
    xor a
    call fill_memory
    ld hl,INPUT_BASE+GRID_STRIDE
    ld de,INPUT_BASE
    ld bc,160
    ldir
    ld hl,INPUT_BASE+160
    ld bc,80
    ld a,32
    jp fill_memory
scroll_command: dw 16,168,16,160,480,16
    db 0,0,&D0
clear_editor_command: dw 0,0,16,176,480,8
    db 17,0,&C0

; Detect a one-cell shift against the rendered cache, then move pixels on VDP.
; Comparing the actual new grid makes this safe at explicit LF boundaries too.
vdp_shift_editor:
    ld a,(fast_start_row)
    ld (shift_row),a
    ld a,(fast_start_col)
    ld (shift_col),a
shift_next_row:
    xor a
    ld (shift_changed),a
    ld a,(shift_col)
    cp 79
    jp nc,shift_row_done
    ld a,(shift_row)
    sub STATUS_ROW
    ld l,a
    ld h,0
    call grid_row_offset
    ld de,RENDER_CACHE
    add hl,de
    ld (shift_cache),hl
    ld a,(shift_col)
    ld e,a
    ld d,0
    add hl,de
    push hl
    ld a,(shift_row)
    call grid_row_address
    ld a,(shift_col)
    ld e,a
    ld d,0
    ld a,(shift_left)
    or a
    jp nz,shift_compare_left
    inc e
shift_compare_left:
    add hl,de
    ex de,hl
    pop hl
    ld a,(shift_left)
    or a
    jp z,shift_compare_ready
    inc hl
shift_compare_ready:
    ld a,(shift_col)
    ld b,a
    ld a,79
    sub b
    ld b,a
shift_compare:
    ld a,(de)
    cp (hl)
    jp nz,shift_row_done
    ld a,(shift_changed)
    or a
    jp nz,shift_compare_next
    push hl
    ld a,(shift_left)
    or a
    jp nz,shift_destination_left
    inc hl
    jp shift_destination_test
shift_destination_left:
    dec hl
shift_destination_test:
    ld a,(de)
    cp (hl)
    pop hl
    jp z,shift_compare_next
    ld a,1
    ld (shift_changed),a
shift_compare_next:
    inc de
    inc hl
    djnz shift_compare
    ld a,(shift_changed)
    or a
    jp z,shift_row_done
    ld a,(shift_col)
    ld b,a
    ld a,79
    sub b
    ld l,a
    ld h,0
    add hl,hl
    ld d,h
    ld e,l
    add hl,hl
    add hl,de
    ld (shift_command+8),hl
    ld a,(shift_left)
    or a
    jp nz,shift_setup_left
    ld hl,488
    ld (shift_command),hl
    ld hl,494
    ld (shift_command+4),hl
    ld a,4
    ld (shift_command+13),a
    jp shift_setup_y
shift_setup_left:
    ld a,(shift_col)
    ld l,a
    ld h,0
    add hl,hl
    ld d,h
    ld e,l
    add hl,hl
    add hl,de
    ld de,16
    add hl,de
    ld (shift_command+4),hl
    ld de,6
    add hl,de
    ld (shift_command),hl
    xor a
    ld (shift_command+13),a
shift_setup_y:
    ld a,(shift_row)
    add a,a
    add a,a
    add a,a
    ld l,a
    ld h,0
    ld (shift_command+2),hl
    ld (shift_command+6),hl
    ld hl,shift_command
    call vdp_command
    call vdp_wait
    ld a,(shift_left)
    or a
    jp nz,shift_cache_left
    ld hl,(shift_cache)
    ld de,78
    add hl,de
    ld d,h
    ld e,l
    inc de
    ld a,(shift_col)
    ld b,a
    ld a,79
    sub b
    ld c,a
    ld b,0
    push bc
    lddr
    ld hl,(shift_cache)
    ld de,398
    add hl,de
    ld d,h
    ld e,l
    inc de
    pop bc
    lddr
    jp shift_row_done
shift_cache_left:
    ld hl,(shift_cache)
    ld a,(shift_col)
    ld e,a
    ld d,0
    add hl,de
    ld d,h
    ld e,l
    inc hl
    ld a,(shift_col)
    ld b,a
    ld a,79
    sub b
    ld c,a
    ld b,0
    push bc
    push hl
    ldir
    pop hl
    ld de,320
    add hl,de
    ld d,h
    ld e,l
    dec de
    pop bc
    ldir
shift_row_done:
    xor a
    ld (shift_col),a
    ld a,(shift_row)
    inc a
    ld (shift_row),a
    cp INPUT_ROW+INPUT_ROWS
    jp c,shift_next_row
    ret
shift_row: db INPUT_ROW
shift_col: db 0
shift_cache: dw 0
shift_command: dw 488,0,494,0,0,8
    db 0,4,&D0

shift_changed: db 0

default rel
global itoa, strlen, write_to_screen, write_int_left_aligned, render_buffer_colored, draw_panel

MAX_COLOR_ESC_SEQ_SIZE  equ 17  ; Counting two spaces

section .rodata
    ; === COLORS ===
    color_prefix_seq            db `\e[48;5;`   ; Background (for visible spaces)
    color_prefix_seq_len        equ $-color_prefix_seq
    color_after_code_seq        db `m`
    color_after_code_seq_len    equ $-color_after_code_seq
    color_suffix_seq            db `\e[0m`
    color_suffix_seq_len        equ $-color_suffix_seq


section .text

; =======  Terminal Rendering  ============================================== ;

; Writes the given str to the screen at (X,Y), where (1,1) is the top-left
; corner. We'll use the `\x1b[Y;XH` cursor control sequence to position it.
; Errors out when X and/or Y > 999 or < 1
; Arguments:
;   rdi - Pointer to the str buffer
;   rsi - Length of the str
;   rdx - X as an integer
;   r10 - Y as an integer
; Return:
;   rax - Number of bytes written
write_to_screen:
    push rbx
    mov rbx, r10

    ; Terminal dimensions don't realistically exceed (999, 999)
    cmp rdx, 999
    ja .error
    cmp rbx, 999
    ja .error

    cmp rdx, 1
    jb .error
    cmp rbx, 1
    jb .error

    ; === PROLOGUE ===
    ; Stack frame for the function
    push rbp
    mov rbp, rsp
    sub rsp, 10                 ; X (3B) + Y (3B) + `\x1b`, `[`, `;`, `H`

    ; Save originals for later
    push rsi
    push rdi 
    push rdx

    mov byte [rbp-10], `\x1b`
    mov byte [rbp-9], `[`

    mov rdi, rbx                ; Y coordinate
    lea rsi, [rbp-8]
    call itoa

    mov rbx, rax                ; Y str len
    mov byte [rbp-8+rbx], `;`

    pop rdi                     ; X coordinate (rdx in stack)
    lea rsi, [rbp-7+rbx]        ; 8 accounts for the `;`
    call itoa

    add rbx, rax                ; Y + X str len
    mov byte [rbp-7+rbx], `H`

    ; Print the ANSI escape string to position cursor
    mov rax, 1
    mov rdi, 1
    lea rsi, [rbp-10]
    lea rdx, [rbx+4]
    syscall

    cmp rax, rdx                ; null terminator is not written
    jne .error_post_prologue

    ; Print the actual string
    mov rax, 1
    mov rdi, 1
    pop rsi
    pop rdx
    syscall

    ; Restore stack
    mov rsp, rbp
    pop rbp

    pop rbx
    ret

    .error_post_prologue:
        mov rsp, rbp
        pop rbp
        pop rbx
        mov rax, 0
        ret

    .error:
        pop rbx
        mov rax, 0
        ret

; Renders an integer value to the screen with right alignment. If the rendered
; digit count is smaller than the specified maximum digit count, left padding
; is added so the value remains visually aligned.
; Arguments:
;   rdi - Integer value to render
;   rsi - Length of destination field. Must be greater or equal than the maximum
;         digit count for the rendered value (e.g. 3 for rdi = 120)
;   rdx - X coordinate
;   r10 - Y coordinate
;   r8 - Length 
; Return:
;   None
write_int_left_aligned:
    push r15
    push r14
    push r13
    push r12

    mov r15, rsi
    mov r14, rdx
    mov r13, r10
    
    sub rsp, r15

    ; rdi already set
    mov rsi, rsp
    call itoa

    mov r12, rax        ; Size of str

    mov r8, r15
    sub r8, r12         ; Alignment
    jz .print_value

    ; --- Alignment required ---
    sub rsp, r8         ; Reserve space BEFORE the str to place alignment
    mov r9, rsp

    mov rax, 0x20
    mov rdi, rsp
    mov rcx, r8
    cld                 ; Makes sure stosb runs forward
    rep stosb

    push r8

    mov rdi, r9         ; push advances rsp
    mov rsi, r8
    mov rdx, r14
    mov r10, r13
    call write_to_screen

    pop r8
    add rsp, r8

    .print_value:
        mov rdi, rsp
        mov rsi, r12
        mov rdx, r14
        add rdx, r8
        mov r10, r13
        call write_to_screen

    add rsp, r15

    pop r12
    pop r13
    pop r14
    pop r15
    ret

; Converts a buffer (line/piece part) into colored ANSI blocks and renders them
; to the screen. To scale the visual output, each cell is duplicated horizontally when
; rendered.
; Arguments:
;   rdi - Source buffer address
;   rsi - Buffer length (number of cells)
;   rdx - Screen X position
;   r10 - Screen Y position
; Returns:
;   rax - Number of cells processed
render_buffer_colored:
    push rbp
    mov rbp, rsp

    push r15
    push r14
    push r13
    push r12
    push rbx

    push rdi                    ; Save for later use

    imul r8, rsi, MAX_COLOR_ESC_SEQ_SIZE
    sub rsp, r8

    mov r15, rdx
    mov r14, r10
    mov rbx, rsi

    mov r13, rsp        ; dst pointer
    mov r12, rdi        ; src pointer

    .render_cell:
        cmp byte [r12], 0x20
        je .render_space

        ; Better than movsb for 8-bytes or smaller str. Doesn't matter if
        ; length != qword, overflow bytes will be overwritten below
        mov rax, qword [color_prefix_seq]
        mov qword [r13], rax
        add r13, color_prefix_seq_len

        movzx edi, byte [r12]
        mov rsi, r13
        call itoa

        add r13, rax

        movzx eax, byte [color_after_code_seq]
        mov [r13], al
        add r13, color_after_code_seq_len

        mov word [r13], 0x2020
        add r13, 2

        mov eax, [color_suffix_seq]
        mov [r13], eax
        add r13, color_suffix_seq_len

        jmp .continue

        .render_space:
            mov word [r13], 0x2020
            add r13, 2

        .continue:
            inc r12
            dec rbx
            jnz .render_cell

    mov rdi, rsp        ; arg 1: buffer pointer
    mov rsi, r13
    sub rsi, rsp        ; arg 2: length = end_ptr - start_ptr
    mov rdx, r15        ; arg 3: X
    mov r10, r14        ; arg 3: Y
    call write_to_screen
    
    ; Restore stack to the location it was after the 6 register push (6 * 8 = 48 bytes)
    lea rsp, [rbp - 48]

    pop rdi

    mov rax, r12
    sub rax, rdi        ; We return this (bytes read: src_end - src_start)

    pop rbx
    pop r12
    pop r13
    pop r14
    pop r15

    leave
    ret

; Draws a given panel (multi-line elem) on the screen at (X,Y), where (1,1) is
; the top-left corner. Renders each line of the panel STARTING at the
; specified coordinates.
; Arguments:
;   rdi - Pointer to panel data: first 4 bytes are metadata (width, height,
;         x-offset, y-offset), followed by height null-terminated string rows
; Return:
;   rax - Success (0) or error (-1)
draw_panel:
    ; === PROLOGUE ===
    push r15
    push r14
    push r13
    push r12

    xor r12, r12
    xor r13, r13
    xor r14, r14
    xor r15, r15

    mov r12b, byte [rdi+1]      ; height
    mov r13b, byte [rdi+2]      ; col (X)
    mov r14b, byte [rdi+3]      ; line (Y)
    add r12b, r14b              ; end_Y = height + starting line (Y)
    lea r15, [rdi+4]            ; data
    
    .print_lines:
        mov rdi, r15
        mov rsi, 1024
        call strlen

        cmp rax, 1024
        je .error

        mov rdi, r15
        mov rsi, rax
        mov rdx, r13
        mov r10, r14
        call write_to_screen

        lea r15, [r15+rax+1]    ; next line
        inc r14

        cmp r14, r12
        jb .print_lines         ; not all lines printed?

    mov rax, 0
    jmp .return

    .error:
        mov rax, 1

    .return:
        pop r12
        pop r13
        pop r14
        pop r15

        ret


; =======  Utils  =========================================================== ;

; Converts an integer into its ASCII representation
; Arguments:
;   rdi - Integer
;   rsi - Pointer to the caller-allocated buffer
; Return:
;   rax - Length of the generated string
itoa:
    mov rax, rdi
    mov r9, 10
    xor r10, r10          ; str ptr
    xor r11, r11          ; Pushed digits

    .get_digits:
        xor rdx, rdx
        div r9

        push rdx
        inc r11

        test rax, rax
        jnz .get_digits

    mov rax, r11         ; str len (ret value)

    .digit_to_ascii:
        pop r9         ; Retrieves digits in correct order
        dec r11

        lea rcx,  [r9 + '0']
        mov byte [rsi + r10], cl
        inc r10

        test r11, r11
        jnz .digit_to_ascii

    mov byte [rsi + r10], 0x0
    ret

; Returns the byte-length of a given string up-to 1024 bytes. If the string has
; multi-byte UTF-8 characters, each byte is counted individually.
; Arguments:
;   rdi - Pointer to the null-terminated string buffer
;   rsi - Maximum number of characters to examine
; Return:
;   rax - Byte-length of the string (excluding null terminator), or zero if str
;         is a null pointer, and rsi if the null character was not found in the
;         first rsi bytes.
strlen:
    xor eax, eax            ; al = 0
    test rdi, rdi
    jz .done

    cld                     ; Ensure we are scanning FORWARD
    mov rcx, rsi

    repne scasb             ; Scan while [rdi] != al AND rcx != 0

    xor rdi, rdi
    setz dil                ; Save og ZF flag

    mov rax, rsi
    sub rax, rcx            ; rax = bytes_scanned
    
    test dil, dil
    jz .done                ; ZF=0 -> no null found, we hit limit -> rax == rsi
    dec rax                 ; ZF=1 -> found null -> exclude null from length

    .done:
        ret
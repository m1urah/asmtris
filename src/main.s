global _start

default rel
section .rodata
    ;# enter alternate buffer -> clear screen -> hide cursor
    clear_seq               db `\x1b[?1049h\x1b[2J\x1b[3J\x1b[H\x1b[?25l`
    clear_len               equ $-clear_seq

    ;# disables buffer -> show cursor
    return_seq              db `\x1b[?1049l\x1b[?25h`
    return_len              equ $-return_seq

    cursor_home             db `\x1b[H`
    cursor_home_len         equ $-cursor_home

    error_str_cords         db "Error: coordinates cannot exceed (999, 999)"
    error_str_cords_len     equ $-error_str_cords

    ;# struct sigaction, each field is 8 bytes
    sa_struct:
        dq exit_handler     ;# sa_handler
        dq 0x04000000       ;# sa_flags (SA_RESTORER)
        dq exit_restorer    ;# sa_restorer
        dq 0                ;# sa_mask


section .text
_start:
    ;# rt_sigaction
    mov rdi, 2              ;# SIGINT (CTRL+C)
    lea rsi, [sa_struct]
    mov rdx, 0
    mov r10, 8
    mov rax, 13
    syscall

    mov rdi, 20             ;# SIGTSTP (CTRL+Z)
    mov rax, 13
    syscall

    call clear_screen

    sub rsp, 5

    mov dword [rsp], "hola"
    mov byte[rsp-4], `\0`
    lea rdi, [rsp]
    mov rsi, 4
    call _write

    add rsp, 5

    mov rsi, 15
    mov rdx, 3
    call _write_to_screen

    .infinity:
        pause
        jmp .infinity

exit_handler:
    call clear_screen
    call restore_screen

    mov rdi, 0
    mov rax, 60
    syscall

exit_restorer:
    ;# rt_sigreturn
    mov rax, 15
    syscall
    ret

clear_screen:
    ;# write (clear screen)
    mov rdi, 1
    lea rsi, [clear_seq]
    mov rdx, clear_len 
    mov rax, 1
    syscall

    ret

restore_screen:
    ;# write
    mov rdi, 1
    lea rsi, [return_seq]
    mov rdx, return_len 
    mov rax, 1
    syscall

    ret


;# =======  Helpers  ======================================================== #

;#  Writes the given str to the screen at (X,Y), where (0,0) is the top-left
;#  corner. We'll use the `\x1b[Y;XH` cursor control sequence to position it.
;#  Arguments:
;#    rdi - Pointer to the str buffer
;#    rsi - X as an integer
;#    rdx - Y as an integer
;#  Return:
;#    None
_write_to_screen:
    ;# terminal dimensions don't realistically exceed (999, 999)
    cmp rsi, 999
    ja .error
    cmp rdx, 999
    ja .error

    ;# --- PROLOGUE ---
    ;# stack frame for the function
    push rbp
    mov rbp, rsp
    sub rsp, 11                 ;# X (3B) + Y (3B) + `\x1b`, `[`, `;`, `H` + \0

    push r12
    push rsi

    mov byte [rbp-11], `\x1b`
    mov byte [rbp-10], `[`

    mov rdi, rdx                ;# Y
    lea rsi, [rbp-9]
    call _itoa

    mov r12, rax                ;# Y str len
    mov byte [rbp-9+r12], `;`

    pop rdi                     ;# X
    lea rsi, [rbp-8+r12]        ;# 8 accounts for the ;
    call _itoa

    add r12, rax                ;# Y + X str len
    mov byte [rbp-8+r12], `H`

    lea rdi, [rbp-11]
    lea rsi, [r12+5]
    xor rdx, rdx
    call _write
    
    sub rsp, 3
    mov dword [rbp-14], "Hell"
    mov dword [rbp-10], "o, W"
    mov dword [rbp-6], "orld"
    mov byte [rbp-2], "!"
    mov byte[rbp-1], `\0`
    lea rdi, [rbp-14]
    mov rsi, 14
    call _write

    ;# cleanup stack
    pop r12
    mov rsp, rbp
    pop rbp

    ret

    .error:
        call restore_screen

        mov rdi, error_str_cords
        mov rsi, error_str_cords_len
        mov rdx, 1
        call _write

        mov rdi, 1
        mov rax, 60
        syscall

;#  Converts an integer into its ASCII representation
;#  Arguments:
;#    rdi - Integer
;#    rsi - Pointer to the caller-allocated buffer
;#  Return:
;#    rax - Length of the generated string
_itoa:
    mov rax, rdi
    mov rbx, 10
    xor r8, r8        ;# str ptr
    xor r9, r9        ;# pushed digits

    .get_digits:
        xor rdx, rdx
        div rbx

        push rdx
        inc r9

        test rax, rax
        jnz .get_digits

    mov rax, r9        ;# str len (ret value)

    .digit_to_ascii:
        pop rbx         ;# retrieves digits in correct order
        dec r9

        lea rcx,  [rbx + '0']
        mov byte [rsi + r8], cl
        inc r8

        test r9, r9
        jnz .digit_to_ascii

    mov byte [rsi + r8], 0x0   ;# null terminator
    ret

;#  Writes the given str to stdout with a new line
;#  Arguments:
;#    rdi - Pointer to the str buffer
;#    rsi - Length
;#    rdx - Wether to print newline (1) or not (0)
;#  Return:
;#    None
_write:
    mov r8, rdi
    mov r9, rsi
    xor r10, r10

    cmp rdx, 1
    jne .default_val
    mov r10, 1

    .default_val:
        mov rdi, 1
        mov rsi, r8
        mov rdx, r9
        mov rax, 1
        syscall

        test r10, r10
        jz .exit

        dec rsp
        mov byte [rsp], `\n`

        mov rdi, 1
        mov rsi, rsp
        mov rdx, 1
        mov rax, 1
        syscall

        inc rsp

    .exit:
        ret
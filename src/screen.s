global setup_board
extern write_to_screen
default rel

section .rodata
    ;# Enter alternate buffer -> clear screen -> hide cursor
    clear_seq           db `\x1b[?1049h\x1b[2J\x1b[3J\x1b[H\x1b[?25l`
    clear_len           equ $-clear_seq

    hello_world         db "Hello, World 1!"
    hello_world_len     equ $-hello_world
    hello_world_2       db "Hello, World 2!"
    hello_world_3       db "Hello, World 3!"


section .text

; Entrypoint for the screen module. Setups the board in the alternate buffer by
; cleaning the screen, and placing all panels.
; Arguments:
;   None
; Return:
;   None
setup_board:
    ; Enter alternate buffer and clear screen
    mov rax, 1
    mov rdi, 1
    lea rsi, [clear_seq]
    mov rdx, clear_len
    syscall

    call _print_test
    ret


; =======  Helpers  ======================================================== #

_print_test:
    mov rdi, hello_world
    mov rsi, hello_world_len
    mov rdx, 0
    mov r10, 0
    call write_to_screen

    test rax, rax
    jne .error

    lea rdi, [hello_world_2]
    mov rsi, hello_world_len
    mov rdx, 7
    mov r10, 7
    call write_to_screen

    test rax, rax
    jne .error

    lea rdi, [hello_world_3]
    mov rsi, hello_world_len
    mov rdx, 3
    mov r10, 3
    call write_to_screen

    test rax, rax
    jne .error

    ret

    .error:
        mov rdi, rax
        mov rax, 60
        syscall
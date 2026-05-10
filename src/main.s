global _start
extern init_board, init_screen, process_input, update_screen, gravity_tick
extern verify_game_over, render_game_over
default rel

section .rodata
    ; =======  STRUCTS  ==================================================== #
    ; man 2 sigaction
    sa_struct:
        dq exit_handler     ; sa_handler
        dq 0x04000000       ; sa_flags (SA_RESTORER)
        dq exit_restorer    ; sa_restorer
        dq 0                ; sa_mask

    ; man 3 timespec
    timespec_struct:
        dq 0                ; tv_sec
        dq 16666666         ; tv_nsec (aprox 60fps)


    ; ======  STRINGS  ===================================================== #
    ; disables buffer -> show cursor
    return_seq              db `\x1b[?1049l\x1b[?25h`
    return_len              equ $-return_seq

    cursor_home             db `\x1b[H`
    cursor_home_len         equ $-cursor_home

    read_res                db "You wrote: "
    read_res_len            equ $-read_res


section .bss
    ; Ref https://github.com/torvalds/linux/blob/master/include/uapi/asm-generic/termbits.h#L30
    ; with NCSS = 32
    termios_struct_og       resb 64    ; Backup of original settings
    termios_struct_mod      resb 64    ; Settings we modify


section .text
_start:
    call init_env
    sub rsp, 4                      ; User input buffer

; Starts a new game by resetting game state, initializing the board and screen,
; and entering the main game loop, where input, physics are processed until end
; of game.
; Arguments:
;   None
; Return:
;   Does not return
start_game:
    call init_board
    call init_screen

    .infinity:
        call sleep

        .read_user_input:
            mov rax, 0
            mov rdi, 0
            mov rsi, rsp
            mov rdx, 3
            syscall

            mov r13, rax    
            test r13, r13
            jz .continue_loop       ; No input?

            cmp byte [rsp], "q"
            je exit_handler

            mov rdi, rsp
            mov rsi, r13
            call process_input

        .continue_loop:
            call verify_game_over
            test rax, rax
            jnz game_over

            call gravity_tick
            call update_screen
            jmp .infinity

; Displays the final game screen and waits for user input to either restart the
; game or exit the program.
; Arguments:
;   None
; Return:
;   Does not return (either restarts game or exits process)
game_over:
    call render_game_over

    .get_user_decision:
        call sleep

        ; Read user input
        mov rax, 0
        mov rdi, 0
        mov rsi, rsp
        mov rdx, 3
        syscall

        mov r13, rax    
        test r13, r13
        jz .get_user_decision   ; No input?

        cmp byte [rsp], "q"
        je exit_handler

        cmp byte [rsp], 0x20
        je start_game

        jmp .get_user_decision


; =======  Environment  ===================================================== ;

; Initializes the terminal environment by setting up signal handlers for CTRL+C
; and CTRL+Z, and disabling terminal buffering and echoing for real-time input
; processing.
; Arguments:
;   None
; Return:
;   None
init_env:
    ; sys_rt_sigaction
    mov rax, 13             
    mov rdi, 2              ; SIGINT (CTRL+C)
    lea rsi, [sa_struct]
    mov rdx, 0              ; Don't wan no oldact
    mov r10, 8
    syscall

    ; sys_rt_sigaction
    mov rax, 13             ; SIGTSTP (CTRL+Z)
    mov rdi, 20
    syscall
    
    call modify_termios

    ret

; Sleeps the amount of time specified in the timespec_struct's tv_nsec field.
; Arguments:
;   None
; Return:
;   None
sleep:
    ; sys_nanosleep
    mov rax, 35
    lea rdi, [timespec_struct]
    mov rsi, 0
    syscall

    ret

; Restores the terminal state and terminates the process.
; Intended to be used both as a signal handler and normal exit routine.
; Arguments:
;   None
; Return:
;   Does not return
exit_handler:
    call restore_screen

    mov rdi, 0
    mov rax, 60
    syscall

; Signal restorer used by rt_sigaction with SA_RESTORER. Returns execution flow
; back to the kernel after signal handling.
; Arguments:
;   None
; Return:
;   None
exit_restorer:
    ; rt_sigreturn
    mov rax, 15
    syscall
    ret

; Restores the original terminal configuration and returns the terminal to the
; normal screen buffer with the cursor visible.
; Arguments:
;   None
; Return:
;   None
restore_screen:
    %define TCSETS          0x5402

    ; sys_ioctl
    mov rax, 16
    mov rdi, 0
    mov rsi, TCSETS
    mov rdx, termios_struct_og
    syscall

    mov rax, 1
    mov rdi, 1
    lea rsi, [return_seq]
    mov rdx, return_len 
    syscall

    ret

; Modify the terminal behavior using the termios struct for real-time keyboard
; input. Disables canonical mode (no need for newline) and input echoing, and
; configures stdin polling to work in non-blocking mode.
; Arguments:
;   None
; Return:
;   rax - Success (0) or error (1)
modify_termios:
    %define TCGETS          0x5401
    %define TCSETS          0x5402
    %define ICANON          0x0002
    %define ECHO            0x0008
    %define VTIME_OFFSET    5
    %define VMIN_OFFSET     6

    ; Get current settings via ioctl
    mov rdi, 0
    mov rsi, TCGETS
    mov rdx, termios_struct_og
    mov rax, 16
    syscall

    ; Copy original in 8 chunks of 8 bytes each
    lea rsi, [termios_struct_og]
    lea rdi, [termios_struct_mod]
    mov rcx, 8      ; 64 bytes / 8
    rep movsq

    ; Disable flags in c_lflag
    mov eax, [termios_struct_mod + 12]  ; offset
    and eax, ~(ICANON | ECHO)           ; bitwise AND NOT
    mov [termios_struct_mod + 12], eax

    ; Set VMIN and VTIME to 0 for non-blocking polling
    mov rax, 17                         ; c_cc offset
    mov byte [termios_struct_mod + rax + VTIME_OFFSET], 0
    mov byte [termios_struct_mod + rax + VMIN_OFFSET], 0

    ; Set new settings via ioctl
    mov rdi, 0
    mov rsi, TCSETS
    mov rdx, termios_struct_mod
    mov rax, 16
    syscall

    ret

default rel
global init_board, process_board_input, gravity_tick, verify_game_over
global game_board, score, level, lines, needs_next_piece_redraw, is_paused
global GAME_BOARD_WIDTH, GAME_BOARD_HEIGHT, NUMBER_OF_HIDDEN_ROWS
extern spawn_piece, choose_next_piece, move_piece, rotate_figure, lock_delay_active     ; piece.s
extern lock_delay, lock_resets, calculate_hard_drop, do_hard_drop, active_piece
extern next_piece, LOCK_DELAY_VALUE, PIECE_STRUCT_MAX_SIZE

NUMBER_OF_HIDDEN_ROWS   equ 4
GAME_BOARD_WIDTH        equ 13
GAME_BOARD_HEIGHT       equ 25      ; 4 first lines = hidden (spawn) zone
GAME_BOARD_SIZE         equ GAME_BOARD_WIDTH * GAME_BOARD_HEIGHT

section .rodata
    level_speeds:   ; Lvl 0, 1, 2 ... 29+
        db 48, 43, 38, 33, 28, 23, 18, 13, 8, 6
        db 5, 5, 5, 4, 4, 4, 3, 3, 3, 2, 2, 2
        db 2, 2, 2, 2, 2, 2, 2, 1

section .data
    ; Logical game board. Possible values:
    ;   - 0x20: empty cell (space)
    ;   - o, i, s, z, l, j, t: identifies part of a piece. Represented as:
    ;       oo  iiii   ss  zz     l  j      t 
    ;       oo        ss    zz  lll  jjj  ttt
    game_board              times GAME_BOARD_SIZE db 0x20

    score                   dd 0
    lines                   dd 0
    level                   db 0
    
    frames_until_drop       db 0
    needs_next_piece_redraw db 0
    is_paused               db 0


section .text

; =======  Entrypoint  ====================================================== ;

; Sets the initial state of the board.
; Arguments:
;   None
; Return:
;   None
init_board:
    ; Set initial state
    mov rax, 0x20

    lea rdi, [game_board]
    mov rcx, GAME_BOARD_SIZE
    rep stosb
    
    lea rdi, [active_piece]
    mov rcx, PIECE_STRUCT_MAX_SIZE
    rep stosb

    lea rdi, [next_piece]
    mov rcx, PIECE_STRUCT_MAX_SIZE
    rep stosb

    mov dword [score], 0
    mov dword [lines], 0
    mov byte [level], 0

    movzx eax, byte [level]
    mov r8b, [level_speeds + rax]       ; Current level speed
    mov byte [frames_until_drop], r8b   ; Reset timer

    mov byte [needs_next_piece_redraw], 1
    mov byte [is_paused], 0

    ; From transforms.s
    mov byte [lock_delay], 0
    mov byte [lock_delay_active], 0
    mov byte [lock_resets], 0

    call choose_next_piece
    call spawn_piece

    ret

; Process all inputs from the user except for quit.
; Arguments:
;   rdi - Pointer to the input buffer
;   rsi - Length of the input
; Return:
;   rax - -1 on quit, 0 otherwise
process_board_input:
    push rbp
    mov rbp, rsp

    push r15
    push r14

    mov r14, 0          ; No quit

    test rsi, rsi
    jz .return
    
    xor r15, r15        ; Down move?

    mov ecx, [rdi]      ; Load 4 bytes (even if it has garbage, we don't care yet)

    ; Route based on exact bytes read
    cmp rsi, 1
    je .handle_1_byte   ; WASD / Space
    
    cmp rsi, 3
    je .handle_3_byte   ; Arrows
    
    jmp .return           ; Ignore 2-byte or 4+-byte keystrokes

    .handle_1_byte:
        ; RSI = 1. We ONLY look at CL
        cmp cl, 'q'
        je .do_quit

        cmp cl, 'p'
        je .do_pause
        cmp cl, `\e`
        je .do_pause

        cmp byte [is_paused], 1
        je .return

        ; Allow movement when piece is partially visible (math done by NASM)
        cmp byte [active_piece + 3], NUMBER_OF_HIDDEN_ROWS - 1
        jl .return

        cmp cl, 'a'
        je .do_left
        cmp cl, 'd'
        je .do_right
        cmp cl, 'w'
        je .do_up
        cmp cl, 's'
        je .do_down
        cmp cl, 0x20
        je .do_space

        jmp .return

    .handle_3_byte:
        ; RSI = 3. Mask to 24 bits (0x00FFFFFF) to ignore the 4th LE byte
        and ecx, 0x00FFFFFF

        cmp byte [is_paused], 1
        je .return

        ; Allow movement when piece is partially visible (math done by NASM)
        cmp byte [active_piece + 3], NUMBER_OF_HIDDEN_ROWS - 1
        jl .return

        cmp ecx, `\e[D`
        je .do_left
        cmp ecx, `\e[C`
        je .do_right
        cmp ecx, `\e[A`
        je .do_up
        cmp ecx, `\e[B`
        je .do_down

        jmp .return

    .do_pause:
        xor byte [is_paused], 1
        mov byte [needs_next_piece_redraw], 1
        jmp .return

    .do_up:     ; rotate
        call rotate_figure
        call calculate_hard_drop
        jmp .return

    .do_left:   ; (-1, 0)
        mov rdi, -1
        mov rsi, 0
        jmp .apply_move

    .do_right:  ; (1, 0)
        mov rdi, 1
        mov rsi, 0
        jmp .apply_move

    .do_down:   ; (0, 1)
        mov rdi, 0
        mov rsi, 1
        mov r15, 1

    .apply_move:
        call move_piece

        test rax, rax
        jz .return        ; Move failed, skip score

        test r15, r15
        jz .update_hd   ; Not a down move, skip score

        ; --- Score Update ---
        mov rdi, 1
        call update_score
        jmp .return

        ; --- Hard Drop Update ---
        .update_hd:
            call calculate_hard_drop
            jmp .return

    .do_space:
        call do_hard_drop
        
        imul rdi, rax, 2    ; 2 points per skipped cell
        call update_score

        jmp .return

    .do_quit:
        mov r14, -1
    
    .return:
        mov rax, r14

        pop r14
        pop r15
        leave
        ret

; Attempts to move the active piece one position down. If the lock delay is
; active and expired, the piece is locked into position, which prompts a new
; piece to be spawned, clearing full lines and updating the score accordingly.
; Arguments:
;   None
; Return:
;   None
gravity_tick:
    cmp byte [is_paused], 1
    je .return

    cmp byte [lock_delay_active], 1
    jne .continue

    dec byte [lock_delay]
    jnz .continue

    ; Disable timer and reset it and stall counter
    mov byte [lock_resets], 0
    mov byte [lock_delay_active], 0
    mov byte [lock_delay], LOCK_DELAY_VALUE

    ; Lock active piece by spawning a new one
    call spawn_piece
    call clear_full_rows

    mov rdi, rax
    call update_score_lines       ; No-op if rdi = 0

    ; Flag that the view needs to update the next piece
    mov byte [needs_next_piece_redraw], 1

    .continue:
        dec byte [frames_until_drop]
        jnz .return

        movzx eax, byte [level]
        mov r8b, [level_speeds + rax]       ; Current level speed
        mov byte [frames_until_drop], r8b   ; Reset timer

        xor rdi, rdi
        mov rsi, 1
        call move_piece     ; Move 1 down (0, 1)

    .return:
        ret


; =======  Row Clearing  ==================================================== ;

; Checks every single non-hidden row on the board from bottom to top, clearing
; full lines.
; Arguments:
;   None
; Return
;   rax - Number cleared lines
clear_full_rows:
    push r15
    push r14

    mov r14, 0                      ; Cleared lines counter (for scoring)
    mov r15, GAME_BOARD_HEIGHT
    dec r15                         ; (Y) Last row (first is 0)

    .check_rows_loop:
        mov rdi, r15
        call _is_line_full

        test rax, rax
        jz .next_row

        ; --- Line is full ---
        mov rdi, r15
        call _shift_rows_down
        inc r14

        inc r15                     ; Need to verify r15 again (content was shifted down)

        .next_row:
            dec r15
            cmp r15, NUMBER_OF_HIDDEN_ROWS
            jae .check_rows_loop

    mov rax, r14
    test rax, rax
    jz .return

    add [lines], r14w

    .return:
        pop r14
        pop r15
        ret

; Checks if given row is completed (no 0x20 bytes).
; Arguments:
;   rdi - Row to check
; Return:
;   rax - 1 (True) full, 0 (False) not full.
_is_line_full:
    mov rax, 0

    cmp rdi, NUMBER_OF_HIDDEN_ROWS
    jl .return                      ; Hidden rows DON'T shift

    ; r8 points to the first byte of the given row
    imul rdx, rdi, GAME_BOARD_WIDTH
    lea r8, [game_board]
    add r8, rdx

    mov rcx, GAME_BOARD_WIDTH

    .check_row_loop:
        cmp byte [r8], 0x20
        je .return
        inc r8
        dec rcx
        jnz .check_row_loop

    mov rax, 1
    .return:
        ret

; It takes the completed Y row and copies every non-hidden row above it down by
; exactly one row, removing the cleared row from the board. Top row is cleared
; with spaces.
; Arguments:
;   rdi - Row to be cleared
; Return:
;   None
_shift_rows_down:
    cmp rdi, NUMBER_OF_HIDDEN_ROWS
    jl .return                      ; Hidden rows DON'T shift

    imul rcx, rdi, GAME_BOARD_WIDTH
    mov rdx, NUMBER_OF_HIDDEN_ROWS
    imul rdx, rdx, GAME_BOARD_WIDTH

    ; r8 (src) points to the last byte of the row directly ABOVE the cleared line
    ; r9 (dst) points to the last byte of the cleared line
    lea r8, [game_board]
    add r8, rcx
    dec r8                          ; rcx is currently at first byte
    
    lea r9, [r8 + GAME_BOARD_WIDTH]

    .shift_loop:
        movzx r10d, byte [r8]
        mov byte [r9], r10b

        dec r8
        dec r9
        dec rcx
        cmp rcx, rdx
        jg .shift_loop

    ; r9 now points to the last BYTE of first NON-HIDDEN row
    mov rcx, GAME_BOARD_WIDTH
    .empty_top_row:
        mov byte [r9], 0x20
        dec r9
        dec rcx
        jnz .empty_top_row

    .return:
        ret


; =======  Scoring  ======================================================== ;

; Calculates and updates the game score based on the number of cleared lines.
; Uses the standard Nintendo-style point system: Base Points * (Level + 1).
; Where base points can be:
;   - 1 line : 40 points
;   - 2 lines: 100 points
;   - 3 lines: 300 points
;   - 4 lines: 1200 points 
; Arguments:
;   rdi - Number of cleared lines
; Return:
;   None
update_score_lines:
    test rdi, rdi
    jz .return

    cmp rdi, 1
    mov rax, 40
    je .calculate

    cmp rdi, 2
    mov rax, 100
    je .calculate

    cmp rdi, 3
    mov rax, 300
    je .calculate

    cmp rdi, 4
    mov rax, 1200
    jne .return                 ; More than 4 clear lines? Smth went wrong

    .calculate:
        movzx ecx, byte [level]
        inc rcx

        xor rdx, rdx
        mul rcx                 ; rax = base points * (level + 1)

    mov rdi, rax
    call update_score

    .return:
        ret

; Updates the score based on the input number.
; Arguments:
;   rdi - The amount of points to add to the score
; Return:
;   None
update_score:
    test rdi, rdi
    jz .return

    add dword [score], edi

    .return:
        ret


; =======  Other  =========================================================== ;

; Checks if any part of a piece is located within the hidden zone. Must be
; called BEFORE a spawning a new piece.
; Arguments:
;   None
; Return:
;   rax - 1 if Game Over, 0 if games continue
verify_game_over:
    mov rax, 0

    cmp byte [lock_delay_active], 1
    jne .return
    cmp byte [lock_delay], 1
    ja .return

    mov rdi, NUMBER_OF_HIDDEN_ROWS - 1

    ; r8 points to the first byte of the LAST hidden row
    imul rdx, rdi, GAME_BOARD_WIDTH
    lea r8, [game_board]
    add r8, rdx

    mov rax, 1
    mov rcx, GAME_BOARD_WIDTH

    .check_row_loop:
        cmp byte [r8], 0x20
        jne .return
        inc r8
        dec rcx
        jnz .check_row_loop

    mov rax, 0

    .return:
        ret
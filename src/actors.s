.globalzp temp, frame

;;; work best as powers of 2 for easily checking bit patterns
;;; if these are changed to be not powers of 2, be sure to check over
;;; logic that works with the actor arrays
.export MAX_ACTORS
MAX_ACTORS = 16
.zeropage
    .exportzp actor_flags, actor_ids, actor_xs, actor_ys, actor_updaters_lo, actor_updaters_hi
    ;;; flag format
    ;;; 76543210
    ;;; |||||||+- [0]   enable collision (other entities can collide with this) [0=off; 1=on]
    ;;; |++++++-- [1-6] unused
    ;;; +-------- [7]   actor exists [0=empty slot; 1=filled slot]
    ;;;
    ;;; only use the first MAX_ACTORS indices. The +1 at the end acts as a sentinel and should not be overwritten
    actor_flags:    .res MAX_ACTORS+1
    ;;; actor id used as index into jump tables and collision data
    ;;; can also be used as a type discriminator
    actor_ids:      .res MAX_ACTORS
    ;;; screen positions for use by renderer and collision check
    actor_xs:       .res MAX_ACTORS
    actor_ys:       .res MAX_ACTORS
    ;;; updater routine address for actor (detailed below)
    actor_updaters_lo:  .res MAX_ACTORS
    actor_updaters_hi:  .res MAX_ACTORS

    .exportzp actor_count, actor_next_idx
    actor_count:    .res 1  ; number of existing actors
    actor_next_idx: .res 1  ; lowest index of actor with bit 7 = 0

.bss 
    ;;; actor specific data
    ;;; for use by actor-specific updater and renderer routines
    .export actor_data0, actor_data1,  actor_data2,  actor_data3
    actor_data0:    .res MAX_ACTORS
    actor_data1:    .res MAX_ACTORS
    actor_data2:    .res MAX_ACTORS
    actor_data3:    .res MAX_ACTORS

    .export actor_updater_ret_addr
    actor_updater_ret_addr:
        .align 2 
        .res 2 

.code

;;; preconditions:
;;;     there must be fewer than MAX_ACTORS actors in existence
;;;
;;; output:
;;;     actor_next_idx is incremented until
;;;     it points to the next empty actor slot (always increments at least once)
;;;
;;; overwrites:
;;;     A, X, actor_next_idx
.export find_next_empty_actor
.proc find_next_empty_actor
    INC actor_count
    LDX actor_next_idx
    ;;; scan forward until arriving at a flag with bit 7 reset
    loop:
        INX
        LDA actor_flags,X
        BMI loop

    STX actor_next_idx
    RTS
.endproc


;;; parameters:
;;;     X:  index of actor to remove (0..MAX_ACTORS)
;;;
;;; output:
;;;     actor at index X is removed and actor_next_idx is updated accordingly
;;;
;;; overwrites:
;;;     A, X
;;;     current
.export remove_actor
.proc remove_actor
    LDA #0
    STA actor_flags,X
    CPX actor_next_idx ; C = !(X < actor_next_idx)
    BCS :+
        STX actor_next_idx ; re-assign if the removed actor idx is lower than old next-idx
    :
    RTS
.endproc


.macro PROCESS_ACTOR updater_return_label
    .local call_addr
    call_addr = temp+0          ; 2 byte address
    LDA actor_flags,X
    BPL updater_return_label    ; skip nonexistant actors
        ;;; fetch update routine index
        LDA actor_updaters_lo,X
        STA call_addr+0
        LDA actor_updaters_hi,X 
        STA call_addr+1
        JMP (call_addr)         ; dive into the update routine
    updater_return_label:
.endmacro

;;; overwrites:
;;;     A, X, temp+0.1, actor_updater_ret_addr
.export process_actors
.proc process_actors
    ret_addr = actor_updater_ret_addr   ; the name is long
    ;;; switch between forward iteration and backward iteration
    ;;; every frame so that rendering produces flicker automatically
    LDA frame
    LSR A
    BCC begin_update_backward

    ;;; fallthrough if C set
    begin_update_forward:
        LDA #<ret_update_forward
        STA ret_addr+0
        LDA #>ret_update_forward
        STA ret_addr+1
        LDX #0
    update_forward:
        PROCESS_ACTOR ret_update_forward
        INX
        CPX #MAX_ACTORS
        BNE update_forward
    RTS

    begin_update_backward:
        LDA #<ret_update_backward
        STA ret_addr+0
        LDA #>ret_update_backward
        STA ret_addr+1
        LDX #MAX_ACTORS
    update_backward:
        DEX
        PROCESS_ACTOR ret_update_backward
        TXA
        BNE update_backward
    RTS
.endproc

;;; calling convention for update routines:
;;; parameters:
;;;     X:                          index of actor being updated
;;;     actor_updater_ret_addr:     return address
;;;
;;; must preserve:
;;;     X, actor_updater_ret_addr
;;;
;;; return by JMP (actor_updater_ret_addr) or equivalent 

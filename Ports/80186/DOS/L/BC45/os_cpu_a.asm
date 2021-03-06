;********************************************************************************************************
;                                              uC/OS-II
;                                        The Real-Time Kernel
;
;                    Copyright 1992-2020 Silicon Laboratories Inc. www.silabs.com
;
;                                 SPDX-License-Identifier: APACHE-2.0
;
;               This software is subject to an open source license and is distributed by
;                Silicon Laboratories Inc. pursuant to the terms of the Apache License,
;                    Version 2.0 available at www.apache.org/licenses/LICENSE-2.0.
;
;********************************************************************************************************

;********************************************************************************************************
;
;                                          80186 Specific code
;                                          LARGE MEMORY MODEL
;
;                                          Borland C/C++ V4.51
;                                      (IBM/PC Compatible Target)
;
; Filename : os_cpu_a.asm
; Version  : V2.93.00
;********************************************************************************************************

;********************************************************************************************************
;                                    PUBLIC and EXTERNAL REFERENCES
;********************************************************************************************************

            PUBLIC _OSTickISR
            PUBLIC _OSStartHighRdy
            PUBLIC _OSCtxSw
            PUBLIC _OSIntCtxSw

            EXTRN  _OSIntExit:FAR
            EXTRN  _OSTimeTick:FAR
            EXTRN  _OSTaskSwHook:FAR

            EXTRN  _OSIntNesting:BYTE
            EXTRN  _OSPrioHighRdy:BYTE
            EXTRN  _OSPrioCur:BYTE
            EXTRN  _OSRunning:BYTE
            EXTRN  _OSTCBCur:DWORD
            EXTRN  _OSTCBHighRdy:DWORD

.MODEL      LARGE
.CODE
.186
            PAGE
;*********************************************************************************************************
;                                          START MULTITASKING
;                                       void OSStartHighRdy(void)
;
; The stack frame is assumed to look as follows:
;
; OSTCBHighRdy->OSTCBStkPtr --> DS                               (Low memory)
;                               ES
;                               DI
;                               SI
;                               BP
;                               SP
;                               BX
;                               DX
;                               CX
;                               AX
;                               OFFSET  of task code address
;                               SEGMENT of task code address
;                               Flags to load in PSW
;                               OFFSET  of task code address
;                               SEGMENT of task code address
;                               OFFSET  of 'p_arg'
;                               SEGMENT of 'p_arg'               (High memory)
;
; Note : OSStartHighRdy() MUST:
;           a) Call OSTaskSwHook() then,
;           b) Set OSRunning to TRUE,
;           c) Switch to the highest priority task.
;*********************************************************************************************************

_OSStartHighRdy  PROC FAR

            MOV    AX, SEG _OSTCBHighRdy          ; Reload DS
            MOV    DS, AX                         ;
;
            CALL   FAR PTR _OSTaskSwHook          ; Call user defined task switch hook
;
            MOV    AL, 1                          ; OSRunning = TRUE;
            MOV    BYTE PTR DS:_OSRunning, AL     ;   (Indicates that multitasking has started)
;
            LES    BX, DWORD PTR DS:_OSTCBHighRdy ; SS:SP = OSTCBHighRdy->OSTCBStkPtr
            MOV    SS, ES:[BX+2]                  ;
            MOV    SP, ES:[BX+0]                  ;
;
            POP    DS                             ; Load task's context
            POP    ES                             ;
            POPA                                  ;
;
            IRET                                  ; Run task

_OSStartHighRdy  ENDP

            PAGE
;*********************************************************************************************************
;                                PERFORM A CONTEXT SWITCH (From task level)
;                                           void OSCtxSw(void)
;
; Note(s): 1) Upon entry,
;             OSTCBCur     points to the OS_TCB of the task to suspend
;             OSTCBHighRdy points to the OS_TCB of the task to resume
;
;          2) The stack frame of the task to suspend looks as follows:
;
;                 SP -> OFFSET  of task to suspend    (Low memory)
;                       SEGMENT of task to suspend
;                       PSW     of task to suspend    (High memory)
;
;          3) The stack frame of the task to resume looks as follows:
;
;                 OSTCBHighRdy->OSTCBStkPtr --> DS                               (Low memory)
;                                               ES
;                                               DI
;                                               SI
;                                               BP
;                                               SP
;                                               BX
;                                               DX
;                                               CX
;                                               AX
;                                               OFFSET  of task code address
;                                               SEGMENT of task code address
;                                               Flags to load in PSW             (High memory)
;*********************************************************************************************************

_OSCtxSw    PROC   FAR
;
            PUSHA                                  ; Save current task's context
            PUSH   ES                              ;
            PUSH   DS                              ;
;
            MOV    AX, SEG _OSTCBCur               ; Reload DS in case it was altered
            MOV    DS, AX                          ;
;
            LES    BX, DWORD PTR DS:_OSTCBCur      ; OSTCBCur->OSTCBStkPtr = SS:SP
            MOV    ES:[BX+2], SS                   ;
            MOV    ES:[BX+0], SP                   ;
;
            CALL   FAR PTR _OSTaskSwHook           ; Call user defined task switch hook
;
            MOV    AX, WORD PTR DS:_OSTCBHighRdy+2 ; OSTCBCur = OSTCBHighRdy
            MOV    DX, WORD PTR DS:_OSTCBHighRdy   ;
            MOV    WORD PTR DS:_OSTCBCur+2, AX     ;
            MOV    WORD PTR DS:_OSTCBCur, DX       ;
;
            MOV    AL, BYTE PTR DS:_OSPrioHighRdy  ; OSPrioCur = OSPrioHighRdy
            MOV    BYTE PTR DS:_OSPrioCur, AL      ;
;
            LES    BX, DWORD PTR DS:_OSTCBHighRdy  ; SS:SP = OSTCBHighRdy->OSTCBStkPtr
            MOV    SS, ES:[BX+2]                   ;
            MOV    SP, ES:[BX]                     ;
;
            POP    DS                              ; Load new task's context
            POP    ES                              ;
            POPA                                   ;
;
            IRET                                   ; Return to new task
;
_OSCtxSw    ENDP

            PAGE
;*********************************************************************************************************
;                                PERFORM A CONTEXT SWITCH (From an ISR)
;                                        void OSIntCtxSw(void)
;
; Note(s): 1) Upon entry,
;             OSTCBCur     points to the OS_TCB of the task to suspend
;             OSTCBHighRdy points to the OS_TCB of the task to resume
;
;          2) The stack frame of the task to suspend looks as follows:
;
;             OSTCBCur->OSTCBStkPtr ------>  DS                              (Low memory)
;                                            ES
;                                            DI
;                                            SI
;                                            BP
;                                            SP
;                                            BX
;                                            DX
;                                            CX
;                                            AX
;                                            OFFSET  of task code address
;                                            SEGMENT of task code address
;                                            Flags to load in PSW            (High memory)
;
;
;          3) The stack frame of the task to resume looks as follows:
;
;             OSTCBHighRdy->OSTCBStkPtr --> DS                               (Low memory)
;                                           ES
;                                           DI
;                                           SI
;                                           BP
;                                           SP
;                                           BX
;                                           DX
;                                           CX
;                                           AX
;                                           OFFSET  of task code address
;                                           SEGMENT of task code address
;                                           Flags to load in PSW             (High memory)
;*********************************************************************************************************

_OSIntCtxSw PROC   FAR
;
            CALL   FAR PTR _OSTaskSwHook           ; Call user defined task switch hook
;
            MOV    AX, SEG _OSTCBCur               ; Reload DS in case it was altered
            MOV    DS, AX                          ;
;
            MOV    AX, WORD PTR DS:_OSTCBHighRdy+2 ; OSTCBCur = OSTCBHighRdy
            MOV    DX, WORD PTR DS:_OSTCBHighRdy   ;
            MOV    WORD PTR DS:_OSTCBCur+2, AX     ;
            MOV    WORD PTR DS:_OSTCBCur, DX       ;
;
            MOV    AL, BYTE PTR DS:_OSPrioHighRdy  ; OSPrioCur = OSPrioHighRdy
            MOV    BYTE PTR DS:_OSPrioCur, AL
;
            LES    BX, DWORD PTR DS:_OSTCBHighRdy  ; SS:SP = OSTCBHighRdy->OSTCBStkPtr
            MOV    SS, ES:[BX+2]                   ;
            MOV    SP, ES:[BX]                     ;
;
            POP    DS                              ; Load new task's context
            POP    ES                              ;
            POPA                                   ;
;
            IRET                                   ; Return to new task
;
_OSIntCtxSw ENDP

            PAGE
;*********************************************************************************************************
;                                            HANDLE TICK ISR
;
; Description: This function is called 18.20648 times per second
;
; Arguments  : none
;
; Returns    : none
;
; Note(s)    : The following C-like pseudo-code describe the operation being performed in the code below.
;
;              Save all registers on the current task's stack;
;              OSIntNesting++;
;              if (OSIntNesting == 1) {
;                 OSTCBCur->OSTCBStkPtr = SS:SP
;              }
               INT 81H;                   Chain into DOS every 54.925 mS
;              OSTimeTick();              Notify uC/OS-II that a tick has occured
;              OSIntExit();               Notify uC/OS-II about end of ISR
;              Restore all registers that were save on the current task's stack;
;              Return from Interrupt;
;*********************************************************************************************************
;
_OSTickISR  PROC   FAR
;
            PUSHA                                ; Save interrupted task's context
            PUSH   ES
            PUSH   DS
;
            MOV    AX, SEG(_OSIntNesting)        ; Reload DS
            MOV    DS, AX
            INC    BYTE PTR DS:_OSIntNesting     ; Notify uC/OS-II of ISR
;
            CMP    BYTE PTR DS:_OSIntNesting, 1	 ; if (OSIntNesting == 1)
            JNE    SHORT _OSTickISR1
            MOV    AX, SEG(_OSTCBCur)            ;     Reload DS
            MOV    DS, AX
            LES    BX, DWORD PTR DS:_OSTCBCur    ;     OSTCBCur->OSTCBStkPtr = SS:SP
            MOV    ES:[BX+2], SS                 ;
            MOV    ES:[BX+0], SP                 ;
;
_OSTickISR1:
            INT    081H                          ; Chain into DOS's tick ISR (Interrupt will be cleared by DOS)
;
            CALL   FAR PTR _OSTimeTick           ; Process system tick
;
            CALL   FAR PTR _OSIntExit            ; Notify uC/OS-II of end of ISR
;
            POP    DS                            ; Restore interrupted task's context
            POP    ES
            POPA
;
            IRET                                 ; Return to interrupted task
;
_OSTickISR  ENDP
;
            END

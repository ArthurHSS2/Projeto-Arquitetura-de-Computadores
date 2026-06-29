// =============================================================================
// pl_control.sv
// Unidade de Controle Principal -- RV32I pipelined (P&H secao 4.4)
//
// Decodifica o opcode de 7 bits (estagio ID) e gera os sinais de controle
// que serao propagados pelos registradores de pipeline.
//
// Instrucoes suportadas:
//   R-type  (0110011): add, and, ... (e demais decodificadas via Funct3/7
//                       em pl_alu_ctrl: xor, sll, srl, sra, slt, sltu)
//   I-type  (0010011): addi, andi, ori, slti, slli, srli, srai, ...
//   I-type  (0000011): lb, lh, lw, lbu, lhu      -- largura via Funct3
//   S-type  (0100011): sb, sh, sw                -- largura via Funct3
//   B-type  (1100011): beq, bne, blt, bge, bltu, bgeu  -- condicao via Funct3
//   J-type  (1101111): jal
//   I-type  (1100111): jalr
//   U-type  (0110111): lui
//   U-type  (0010111): auipc
//
// Observacao importante sobre LOAD/STORE: o opcode e o MESMO para todas as
// larguras (byte/half/word); quem distingue LB/LH/LW/LBU/LHU (e SB/SH/SW) e
// o campo Funct3, tratado mais tarde no estagio MEM (pl_datapath), nao aqui.
// Por isso a tabela de sinais abaixo NAO muda para lb/lh/lbu/lhu/sb/sh.
//
// Tabela de sinais de controle:
//   Sinal      | R-type | load | store | branch | jal/jalr | lui | auipc
//   -----------|--------|------|-------|--------|----------|-----|------
//   ALUSrc     |   0    |  1   |   1   |   0    |   X      |  X  |  X
//   MemtoReg   |   0    |  1   |   -   |   -    |   0      |  0  |  0
//   RegWrite   |   1    |  1   |   0   |   0    |   1      |  1  |  1
//   MemRead    |   0    |  1   |   0   |   0    |   0      |  0  |  0
//   MemWrite   |   0    |  0   |   1   |   0    |   0      |  0  |  0
//   Branch     |   0    |  0   |   0   |   1    |   0      |  0  |  0
//   ALUOp      |  10    |  00  |  00   |  01    |   00     | 00  |  00
//   ResultSrc  |  00    |  00  |  00   |  00    |   01     | 10  |  11
//   JumpReg    |   0    |  0   |   0   |   0    | jalr=1   |  0  |  0
//
// ResultSrc seleciona o que entra em ex_mem.alu_result / mem_wb.alu_result
// (resolvido no estagio EX, em pl_datapath):
//   00 = saida da ALU (default; load/store usam para calcular endereco)
//   01 = PC + 4   (endereco de retorno -- JAL/JALR)
//   10 = imediato (LUI)
//   11 = PC + imediato (AUIPC)
// =============================================================================

`timescale 1ns / 1ps

module pl_control (
    input  logic [6:0] Opcode,
    output logic       ALUSrc,
    output logic       MemtoReg,
    output logic       RegWrite,
    output logic       MemRead,
    output logic       MemWrite,
    output logic       Branch,
    output logic [1:0] ALUOp,
    output logic [1:0] ResultSrc,   // NOVO -- mux do dado de write-back (EX)
    output logic       JumpReg      // NOVO -- 1 = JALR (alvo rs1+imm)
);

    localparam R_TYPE = 7'b0110011;
    localparam LOAD   = 7'b0000011;  // lb, lh, lw, lbu, lhu (Funct3 distingue)
    localparam STORE  = 7'b0100011;  // sb, sh, sw           (Funct3 distingue)
    localparam BRANCH = 7'b1100011;  // beq, bne, blt, bge, bltu, bgeu
    localparam I_IMM  = 7'b0010011;  // addi, andi, ori, slti, slli, srli, srai
    localparam JAL    = 7'b1101111;
    localparam JALR   = 7'b1100111;
    localparam LUI    = 7'b0110111;
    localparam AUIPC  = 7'b0010111;

    always_comb begin
        ALUSrc    = 1'b0;
        MemtoReg  = 1'b0;
        RegWrite  = 1'b0;
        MemRead   = 1'b0;
        MemWrite  = 1'b0;
        Branch    = 1'b0;
        ALUOp     = 2'b00;
        ResultSrc = 2'b00;
        JumpReg   = 1'b0;

        case (Opcode)
            R_TYPE: begin
                ALUSrc   = 1'b0;
                MemtoReg = 1'b0;
                RegWrite = 1'b1;
                ALUOp    = 2'b10;
            end
            LOAD: begin                 // lb/lh/lw/lbu/lhu -- mesmo decode
                ALUSrc   = 1'b1;
                MemtoReg = 1'b1;
                RegWrite = 1'b1;
                MemRead  = 1'b1;
                ALUOp    = 2'b00;
            end
            STORE: begin                // sb/sh/sw -- mesmo decode
                ALUSrc   = 1'b1;
                MemWrite = 1'b1;
                ALUOp    = 2'b00;
            end
            BRANCH: begin                // beq/bne/blt/bge/bltu/bgeu
                Branch   = 1'b1;
                ALUOp    = 2'b01;
            end
            I_IMM: begin
                ALUSrc   = 1'b1;   // usar imediato inves de rs2
                MemtoReg = 1'b0;
                RegWrite = 1'b1;
                ALUOp    = 2'b10;  // reuse R-type decode
            end
            JAL: begin
                RegWrite  = 1'b1;
                ResultSrc = 2'b01;  // grava PC+4 (endereco de retorno)
                JumpReg   = 1'b0;   // alvo = PC + imm (J-type)
            end
            JALR: begin
                ALUSrc    = 1'b1;   // (nao usado pelo mux de resultado, mas
                                     //  mantido coerente: JALR le rs1+imm)
                RegWrite  = 1'b1;
                ResultSrc = 2'b01;  // grava PC+4 (endereco de retorno)
                JumpReg   = 1'b1;   // alvo = rs1 + imm (I-type)
            end
            LUI: begin
                RegWrite  = 1'b1;
                ResultSrc = 2'b10;  // grava o imediato diretamente
            end
            AUIPC: begin
                RegWrite  = 1'b1;
                ResultSrc = 2'b11;  // grava PC + imediato
            end
            default: ; // sinais permanecem em zero (seguro)
        endcase
    end

endmodule

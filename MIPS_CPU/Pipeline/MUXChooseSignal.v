// we put all MUXs into this file, input variables are signals and output
// variables are required by some modules
// but doesn't include the signal for RAM and ALU
module MUXChooseSignal(
	
	input ALUSrc1, 
	input ALUSrc2, 
	input EXTOp, 
	input LUOp, 
	input MEM_WB_RegWrite,
	input [1  : 0] MEM_WB_RegDst, 
	input [1  : 0] MEM_WB_MemToReg, 
	input [1  : 0] MemToReg, 
	input [1  : 0] RegDst,
	input [31 : 0] instruction_IN,
	input [31 : 0] instruction_IF_ID, 
	input [31 : 0] instruction_ID_EX, 
	input [31 : 0] instruction_EX_MEM,
	input [1  : 0] ForwardA,  
	input [1  : 0] ForwardB, 
	input [1  : 0] ForwardJR,
	input [31 : 0] ALUOUT, 
	input [31 : 0] ReadData, 
	input [31 : 0] MEM_WB_ALUOUT,
	input [31 : 0] ID_EX_DataBusA, 
	input [31 : 0] DataBusA, 
	input [31 : 0] ID_EX_DataBusB,
	input [31 : 0] instruction_MEM_WB,
	input [2  : 0] ID_EX_PCSrc,
	input [31 : 0] ID_EX_PC,
	input [31 : 0] IF_ID_PC_OUT,
	input [2  : 0] PCSrc,
	input [31 : 0] MEM_WB_PC_OUT,
	input [31 : 0] PC,
	input [31 : 0] EX_MEM_ALUOUT,
	input [31 : 0] EX_MEM_PC_OUT,
	
	output [31 : 0] RESULT_ALUSrc1,
	output [31 : 0] RESULT_ALUSrc2,  // two source required by ALU
	output [31 : 0] RESULT_PCSrc,                    
	output [4  : 0] RESULT_RegDst,
	output [31 : 0] DataBusC,
	output [31 : 0] RESULT_DATABUSB,
	output FinalRegWrite);

	//wire [31 : 0] DataBusC;
	wire [2 : 0] FinalPCSrc;
	//wire [31 : 0] RESULT_ALUSrc1, RESULT_ALUSrc2;  // two source required by ALU              

	wire [31 : 0] RESULT_DATABUSA, FINAL_RESULT_DATABUS_A;
	wire [31 : 0] RESULT_LUOp, RESULT_EXTOp;
	wire [15 : 0] SignExtension;
	wire [31 : 0] ConBA; // beq instruction_in
	wire [31 : 0] ShiftOut;
	wire [31 : 0] ForwardResult;
	wire [31 : 0] JUMP_Address;

	assign RESULT_DATABUSA = (ForwardA == 2'b00) ? ID_EX_DataBusA:
							 (ForwardA == 2'b01) ? DataBusC:
				             (ForwardA == 2'b10) ? EX_MEM_ALUOUT:
				             DataBusC;
	assign RESULT_DATABUSB = (ForwardB == 2'b00) ? ID_EX_DataBusB:
							 (ForwardB == 2'b01) ? DataBusC:
							 (ForwardB == 2'b10) ? EX_MEM_ALUOUT:
							 DataBusC;

	// when EXTOp is 1, we use sign extension
	assign SignExtension = instruction_ID_EX[15] ? 16'b1111_1111_1111_1111 : 0;
	assign RESULT_EXTOp  = EXTOp ? {SignExtension, instruction_ID_EX[15 : 0]} : {16'b0, instruction_ID_EX[15 : 0]};
	assign RESULT_LUOp   = LUOp  ? {instruction_ID_EX[15 : 0], 16'b0} : RESULT_EXTOp;

	// the source of ALU					   
	assign RESULT_ALUSrc1 = ALUSrc1 ? {27'b0, instruction_ID_EX[10 : 6]} : RESULT_DATABUSA;
	assign RESULT_ALUSrc2 = ALUSrc2 ? RESULT_LUOp : RESULT_DATABUSB;				

	// the source of register file (interruption is different)
	// when we enter interruption, we should save the EX_PC, not the ID_PCSrc
	assign JUMP_Address = instruction_IN[31 : 26] == 6'b100011 ? PC : IF_ID_PC_OUT;
	assign DataBusC        = (MemToReg == 3) ? JUMP_Address: // for interruption
							 (MEM_WB_MemToReg == 0 ? MEM_WB_ALUOUT:
							  MEM_WB_MemToReg == 1 ? ReadData:
							  MEM_WB_MemToReg == 2 ? (MEM_WB_PC_OUT + 4):
							  32'd0); 

	// the source of address of register file (interruption is different)
	assign RESULT_RegDst   = (RegDst == 3) ? 5'b11010 : // for interruption
							  (MEM_WB_RegDst == 0 ? instruction_MEM_WB[15 : 11]:  // rd
							   MEM_WB_RegDst == 1 ? instruction_MEM_WB[20 : 16]:  // rt
							   MEM_WB_RegDst == 2 ? 5'b11111:        // $ra (31)
							   5'b00000);                            // xp($26)

	// the source of PC
	assign	RESULT_PCSrc   = FinalPCSrc == 3'b000 ? (PC+4):
							 // beq
							 FinalPCSrc == 3'b001 ? ConBA:
							 // j
							 FinalPCSrc == 3'b010 ? {IF_ID_PC_OUT[31:28], instruction_IF_ID[25: 0], 2'b00}: 
							 // jr
							 FinalPCSrc == 3'b011 ? FINAL_RESULT_DATABUS_A:
							 FinalPCSrc == 3'b100 ? 32'h80000004:   // ILLOP
							 32'h80000008;                          // XADR

	assign ForwardResult = (instruction_EX_MEM[31 : 26] == 6'b000011) ? EX_MEM_PC_OUT+4 : EX_MEM_ALUOUT;

	assign FINAL_RESULT_DATABUS_A = ForwardJR[1] ? (ForwardJR[0] ? DataBusC : ForwardResult):
	                                               (ForwardJR[0] ? ALUOUT   : DataBusA);

	// beq instruction (but J instruction is in a higher level)
	assign FinalPCSrc = (ID_EX_PCSrc == 3'b001 && ALUOUT[0] == 1'b1 && PCSrc != 3'b010 && PCSrc != 3'b011 && PCSrc != 3'b100) ? ID_EX_PCSrc : 
							((PCSrc  == 3'b001) ? 3'b0 : PCSrc);  // avoid a beq instruction before

	// when we are in interrupt, we should use ID RegWrite signal						
	assign FinalRegWrite = (MemToReg == 3) ? 1'b1 : MEM_WB_RegWrite;

	// get the address of branch instruction_in (ConBA)
	leftShift ls(.A(RESULT_EXTOp), .S(ShiftOut));      // left shift
	// here we use extomem_pc, because we should jump to a farer address
	Adder adder(.A(ID_EX_PC+4), .B(ShiftOut), .Z(ConBA));
endmodule

// shift
module leftShift(A, S);
	input [31:0] A;
	output [31:0] S;
	assign S = {A[29:0], 2'b00};
endmodule

// 32bits adder
module Adder(A,B,Z);

	input [31:0] A,B;
	output [31:0] Z;

	FA fa0(.a(A[0]),.b(B[0]),.cin(1'b0),.s(Z[0]),.cout(w0));
	FA fa1(.a(A[1]),.b(B[1]),.cin(w0),.s(Z[1]),.cout(w1));
	FA fa2(.a(A[2]),.b(B[2]),.cin(w1),.s(Z[2]),.cout(w2));
	FA fa3(.a(A[3]),.b(B[3]),.cin(w2),.s(Z[3]),.cout(w3));
	FA fa4(.a(A[4]),.b(B[4]),.cin(w3),.s(Z[4]),.cout(w4));
	FA fa5(.a(A[5]),.b(B[5]),.cin(w4),.s(Z[5]),.cout(w5));
	FA fa6(.a(A[6]),.b(B[6]),.cin(w5),.s(Z[6]),.cout(w6));
	FA fa7(.a(A[7]),.b(B[7]),.cin(w6),.s(Z[7]),.cout(w7));
	FA fa8(.a(A[8]),.b(B[8]),.cin(w7),.s(Z[8]),.cout(w8));
	FA fa9(.a(A[9]),.b(B[9]),.cin(w8),.s(Z[9]),.cout(w9));
	FA fa10(.a(A[10]),.b(B[10]),.cin(w9),.s(Z[10]),.cout(w10));
	FA fa11(.a(A[11]),.b(B[11]),.cin(w10),.s(Z[11]),.cout(w11));
	FA fa12(.a(A[12]),.b(B[12]),.cin(w11),.s(Z[12]),.cout(w12));
	FA fa13(.a(A[13]),.b(B[13]),.cin(w12),.s(Z[13]),.cout(w13));
	FA fa14(.a(A[14]),.b(B[14]),.cin(w13),.s(Z[14]),.cout(w14));
	FA fa15(.a(A[15]),.b(B[15]),.cin(w14),.s(Z[15]),.cout(w15));
	FA fa16(.a(A[16]),.b(B[16]),.cin(w15),.s(Z[16]),.cout(w16));
	FA fa17(.a(A[17]),.b(B[17]),.cin(w16),.s(Z[17]),.cout(w17));
	FA fa18(.a(A[18]),.b(B[18]),.cin(w17),.s(Z[18]),.cout(w18));
	FA fa19(.a(A[19]),.b(B[19]),.cin(w18),.s(Z[19]),.cout(w19));
	FA fa20(.a(A[20]),.b(B[20]),.cin(w19),.s(Z[20]),.cout(w20));
	FA fa21(.a(A[21]),.b(B[21]),.cin(w20),.s(Z[21]),.cout(w21));
	FA fa22(.a(A[22]),.b(B[22]),.cin(w21),.s(Z[22]),.cout(w22));
	FA fa23(.a(A[23]),.b(B[23]),.cin(w22),.s(Z[23]),.cout(w23));
	FA fa24(.a(A[24]),.b(B[24]),.cin(w23),.s(Z[24]),.cout(w24));
	FA fa25(.a(A[25]),.b(B[25]),.cin(w24),.s(Z[25]),.cout(w25));
	FA fa26(.a(A[26]),.b(B[26]),.cin(w25),.s(Z[26]),.cout(w26));
	FA fa27(.a(A[27]),.b(B[27]),.cin(w26),.s(Z[27]),.cout(w27));
	FA fa28(.a(A[28]),.b(B[28]),.cin(w27),.s(Z[28]),.cout(w28));
	FA fa29(.a(A[29]),.b(B[29]),.cin(w28),.s(Z[29]),.cout(w29));
	FA fa30(.a(A[30]),.b(B[30]),.cin(w29),.s(Z[30]),.cout(w30));
	FA fa31(.a(A[31]),.b(B[31]),.cin(w30),.s(Z[31]),.cout(w31));
	
endmodule

module FA(a,b,cin,s,cout);

	input a,b,cin;
	output s,cout;

	assign s=(a^b)^cin;
	assign cout=(a^b)&cin|a&b;

endmodule
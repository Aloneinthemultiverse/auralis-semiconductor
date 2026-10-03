// generated from Liberty by lib2v.py (simulation models for gate-level power analysis)
`timescale 1ns/1ps
module AND2_X1 (A1, A2, ZN);
  input A1;
  input A2;
  output ZN;
  assign ZN = (A1 & A2);
endmodule
module AND2_X2 (A1, A2, ZN);
  input A1;
  input A2;
  output ZN;
  assign ZN = (A1 & A2);
endmodule
module AND2_X4 (A1, A2, ZN);
  input A1;
  input A2;
  output ZN;
  assign ZN = (A1 & A2);
endmodule
module AND3_X1 (A1, A2, A3, ZN);
  input A1;
  input A2;
  input A3;
  output ZN;
  assign ZN = ((A1 & A2) & A3);
endmodule
module AND3_X2 (A1, A2, A3, ZN);
  input A1;
  input A2;
  input A3;
  output ZN;
  assign ZN = ((A1 & A2) & A3);
endmodule
module AND3_X4 (A1, A2, A3, ZN);
  input A1;
  input A2;
  input A3;
  output ZN;
  assign ZN = ((A1 & A2) & A3);
endmodule
module AND4_X1 (A1, A2, A3, A4, ZN);
  input A1;
  input A2;
  input A3;
  input A4;
  output ZN;
  assign ZN = (((A1 & A2) & A3) & A4);
endmodule
module AND4_X2 (A1, A2, A3, A4, ZN);
  input A1;
  input A2;
  input A3;
  input A4;
  output ZN;
  assign ZN = (((A1 & A2) & A3) & A4);
endmodule
module AND4_X4 (A1, A2, A3, A4, ZN);
  input A1;
  input A2;
  input A3;
  input A4;
  output ZN;
  assign ZN = (((A1 & A2) & A3) & A4);
endmodule
module ANTENNA_X1 (A);
  input A;
endmodule
module AOI21_X1 (A, B1, B2, ZN);
  input A;
  input B1;
  input B2;
  output ZN;
  assign ZN = ~(A | (B1 & B2));
endmodule
module AOI21_X2 (A, B1, B2, ZN);
  input A;
  input B1;
  input B2;
  output ZN;
  assign ZN = ~(A | (B1 & B2));
endmodule
module AOI21_X4 (A, B1, B2, ZN);
  input A;
  input B1;
  input B2;
  output ZN;
  assign ZN = ~(A | (B1 & B2));
endmodule
module AOI22_X1 (A1, A2, B1, B2, ZN);
  input A1;
  input A2;
  input B1;
  input B2;
  output ZN;
  assign ZN = ~((A1 & A2) | (B1 & B2));
endmodule
module AOI22_X2 (A1, A2, B1, B2, ZN);
  input A1;
  input A2;
  input B1;
  input B2;
  output ZN;
  assign ZN = ~((A1 & A2) | (B1 & B2));
endmodule
module AOI22_X4 (A1, A2, B1, B2, ZN);
  input A1;
  input A2;
  input B1;
  input B2;
  output ZN;
  assign ZN = ~((A1 & A2) | (B1 & B2));
endmodule
module AOI211_X1 (A, B, C1, C2, ZN);
  input A;
  input B;
  input C1;
  input C2;
  output ZN;
  assign ZN = ~(((C1 & C2) | B) | A);
endmodule
module AOI211_X2 (A, B, C1, C2, ZN);
  input A;
  input B;
  input C1;
  input C2;
  output ZN;
  assign ZN = ~(((C1 & C2) | B) | A);
endmodule
module AOI211_X4 (A, B, C1, C2, ZN);
  input A;
  input B;
  input C1;
  input C2;
  output ZN;
  assign ZN = ~(~(~(((C1 & C2) | B) | A)));
endmodule
module AOI221_X1 (A, B1, B2, C1, C2, ZN);
  input A;
  input B1;
  input B2;
  input C1;
  input C2;
  output ZN;
  assign ZN = ~(((C1 & C2) | A) | (B1 & B2));
endmodule
module AOI221_X2 (A, B1, B2, C1, C2, ZN);
  input A;
  input B1;
  input B2;
  input C1;
  input C2;
  output ZN;
  assign ZN = ~(((C1 & C2) | A) | (B1 & B2));
endmodule
module AOI221_X4 (A, B1, B2, C1, C2, ZN);
  input A;
  input B1;
  input B2;
  input C1;
  input C2;
  output ZN;
  assign ZN = ~(~(~(((C1 & C2) | A) | (B1 & B2))));
endmodule
module AOI222_X1 (A1, A2, B1, B2, C1, C2, ZN);
  input A1;
  input A2;
  input B1;
  input B2;
  input C1;
  input C2;
  output ZN;
  assign ZN = ~(((A1 & A2) | (B1 & B2)) | (C1 & C2));
endmodule
module AOI222_X2 (A1, A2, B1, B2, C1, C2, ZN);
  input A1;
  input A2;
  input B1;
  input B2;
  input C1;
  input C2;
  output ZN;
  assign ZN = ~(((A1 & A2) | (B1 & B2)) | (C1 & C2));
endmodule
module AOI222_X4 (A1, A2, B1, B2, C1, C2, ZN);
  input A1;
  input A2;
  input B1;
  input B2;
  input C1;
  input C2;
  output ZN;
  assign ZN = ~(~(~(((A1 & A2) | (B1 & B2)) | (C1 & C2))));
endmodule
module BUF_X1 (A, Z);
  input A;
  output Z;
  assign Z = A;
endmodule
module BUF_X2 (A, Z);
  input A;
  output Z;
  assign Z = A;
endmodule
module BUF_X4 (A, Z);
  input A;
  output Z;
  assign Z = A;
endmodule
module BUF_X8 (A, Z);
  input A;
  output Z;
  assign Z = A;
endmodule
module BUF_X16 (A, Z);
  input A;
  output Z;
  assign Z = A;
endmodule
module BUF_X32 (A, Z);
  input A;
  output Z;
  assign Z = A;
endmodule
module CLKBUF_X1 (A, Z);
  input A;
  output Z;
  assign Z = A;
endmodule
module CLKBUF_X2 (A, Z);
  input A;
  output Z;
  assign Z = A;
endmodule
module CLKBUF_X3 (A, Z);
  input A;
  output Z;
  assign Z = A;
endmodule
module CLKGATETST_X1 (IQ, CK, E, SE, GCK);
  output IQ;
  input CK;
  input E;
  input SE;
  output GCK;
endmodule
module CLKGATETST_X2 (IQ, CK, E, SE, GCK);
  output IQ;
  input CK;
  input E;
  input SE;
  output GCK;
endmodule
module CLKGATETST_X4 (IQ, CK, E, SE, GCK);
  output IQ;
  input CK;
  input E;
  input SE;
  output GCK;
endmodule
module CLKGATETST_X8 (IQ, CK, E, SE, GCK);
  output IQ;
  input CK;
  input E;
  input SE;
  output GCK;
endmodule
module CLKGATE_X1 (IQ, CK, E, GCK);
  output IQ;
  input CK;
  input E;
  output GCK;
endmodule
module CLKGATE_X2 (IQ, CK, E, GCK);
  output IQ;
  input CK;
  input E;
  output GCK;
endmodule
module CLKGATE_X4 (IQ, CK, E, GCK);
  output IQ;
  input CK;
  input E;
  output GCK;
endmodule
module CLKGATE_X8 (IQ, CK, E, GCK);
  output IQ;
  input CK;
  input E;
  output GCK;
endmodule
module DFFRS_X1 (D, RN, SN, CK, Q, QN);
  input D;
  input RN;
  input SN;
  input CK;
  output Q;
  output QN;
  reg IQ = 1'b0;
  wire IQN = ~IQ;
  wire ck_ = CK;
  always @(posedge ck_ or posedge (~RN) or posedge (~SN))
    if (~RN) IQ <= 1'b0; else if (~SN) IQ <= 1'b1; else IQ <= D;
  assign Q = IQ;
  assign QN = IQN;
endmodule
module DFFRS_X2 (D, RN, SN, CK, Q, QN);
  input D;
  input RN;
  input SN;
  input CK;
  output Q;
  output QN;
  reg IQ = 1'b0;
  wire IQN = ~IQ;
  wire ck_ = CK;
  always @(posedge ck_ or posedge (~RN) or posedge (~SN))
    if (~RN) IQ <= 1'b0; else if (~SN) IQ <= 1'b1; else IQ <= D;
  assign Q = IQ;
  assign QN = IQN;
endmodule
module DFFR_X1 (D, RN, CK, Q, QN);
  input D;
  input RN;
  input CK;
  output Q;
  output QN;
  reg IQ = 1'b0;
  wire IQN = ~IQ;
  wire ck_ = CK;
  always @(posedge ck_ or posedge (~RN) or posedge (1'b0))
    if (~RN) IQ <= 1'b0; else if (1'b0) IQ <= 1'b1; else IQ <= D;
  assign Q = IQ;
  assign QN = IQN;
endmodule
module DFFR_X2 (D, RN, CK, Q, QN);
  input D;
  input RN;
  input CK;
  output Q;
  output QN;
  reg IQ = 1'b0;
  wire IQN = ~IQ;
  wire ck_ = CK;
  always @(posedge ck_ or posedge (~RN) or posedge (1'b0))
    if (~RN) IQ <= 1'b0; else if (1'b0) IQ <= 1'b1; else IQ <= D;
  assign Q = IQ;
  assign QN = IQN;
endmodule
module DFFS_X1 (D, SN, CK, Q, QN);
  input D;
  input SN;
  input CK;
  output Q;
  output QN;
  reg IQ = 1'b0;
  wire IQN = ~IQ;
  wire ck_ = CK;
  always @(posedge ck_ or posedge (1'b0) or posedge (~SN))
    if (1'b0) IQ <= 1'b0; else if (~SN) IQ <= 1'b1; else IQ <= D;
  assign Q = IQ;
  assign QN = IQN;
endmodule
module DFFS_X2 (D, SN, CK, Q, QN);
  input D;
  input SN;
  input CK;
  output Q;
  output QN;
  reg IQ = 1'b0;
  wire IQN = ~IQ;
  wire ck_ = CK;
  always @(posedge ck_ or posedge (1'b0) or posedge (~SN))
    if (1'b0) IQ <= 1'b0; else if (~SN) IQ <= 1'b1; else IQ <= D;
  assign Q = IQ;
  assign QN = IQN;
endmodule
module DFF_X1 (D, CK, Q, QN);
  input D;
  input CK;
  output Q;
  output QN;
  reg IQ = 1'b0;
  wire IQN = ~IQ;
  wire ck_ = CK;
  always @(posedge ck_) IQ <= D;
  assign Q = IQ;
  assign QN = IQN;
endmodule
module DFF_X2 (D, CK, Q, QN);
  input D;
  input CK;
  output Q;
  output QN;
  reg IQ = 1'b0;
  wire IQN = ~IQ;
  wire ck_ = CK;
  always @(posedge ck_) IQ <= D;
  assign Q = IQ;
  assign QN = IQN;
endmodule
module DLH_X1 (D, G, Q);
  input D;
  input G;
  output Q;
  reg IQ = 1'b0;
  wire IQN = ~IQ;
  always @* if (G) IQ = D;
  assign Q = IQ;
endmodule
module DLH_X2 (D, G, Q);
  input D;
  input G;
  output Q;
  reg IQ = 1'b0;
  wire IQN = ~IQ;
  always @* if (G) IQ = D;
  assign Q = IQ;
endmodule
module DLL_X1 (D, GN, Q);
  input D;
  input GN;
  output Q;
  reg IQ = 1'b0;
  wire IQN = ~IQ;
  always @* if (~GN) IQ = D;
  assign Q = IQ;
endmodule
module DLL_X2 (D, GN, Q);
  input D;
  input GN;
  output Q;
  reg IQ = 1'b0;
  wire IQN = ~IQ;
  always @* if (~GN) IQ = D;
  assign Q = IQ;
endmodule
module FA_X1 (A, B, CI, CO, S);
  input A;
  input B;
  input CI;
  output CO;
  output S;
  assign CO = ((A & B) | (CI & (A | B)));
  assign S = (CI ^ (A ^ B));
endmodule
module FILLCELL_X1 ();
endmodule
module TAPCELL_X1 ();
endmodule
module FILLCELL_X2 ();
endmodule
module FILLCELL_X4 ();
endmodule
module FILLCELL_X8 ();
endmodule
module FILLCELL_X16 ();
endmodule
module FILLCELL_X32 ();
endmodule
module HA_X1 (A, B, CO, S);
  input A;
  input B;
  output CO;
  output S;
  assign CO = (A & B);
  assign S = (A ^ B);
endmodule
module INV_X1 (A, ZN);
  input A;
  output ZN;
  assign ZN = ~A;
endmodule
module INV_X2 (A, ZN);
  input A;
  output ZN;
  assign ZN = ~A;
endmodule
module INV_X4 (A, ZN);
  input A;
  output ZN;
  assign ZN = ~A;
endmodule
module INV_X8 (A, ZN);
  input A;
  output ZN;
  assign ZN = ~A;
endmodule
module INV_X16 (A, ZN);
  input A;
  output ZN;
  assign ZN = ~A;
endmodule
module INV_X32 (A, ZN);
  input A;
  output ZN;
  assign ZN = ~A;
endmodule
module LOGIC0_X1 (Z);
  output Z;
  assign Z = 1'b0;
endmodule
module LOGIC1_X1 (Z);
  output Z;
  assign Z = 1;
endmodule
module MUX2_X1 (A, B, S, Z);
  input A;
  input B;
  input S;
  output Z;
  assign Z = ((S & B) | (A & ~S));
endmodule
module MUX2_X2 (A, B, S, Z);
  input A;
  input B;
  input S;
  output Z;
  assign Z = ((S & B) | (A & ~S));
endmodule
module NAND2_X1 (A1, A2, ZN);
  input A1;
  input A2;
  output ZN;
  assign ZN = ~(A1 & A2);
endmodule
module NAND2_X2 (A1, A2, ZN);
  input A1;
  input A2;
  output ZN;
  assign ZN = ~(A1 & A2);
endmodule
module NAND2_X4 (A1, A2, ZN);
  input A1;
  input A2;
  output ZN;
  assign ZN = ~(A1 & A2);
endmodule
module NAND3_X1 (A1, A2, A3, ZN);
  input A1;
  input A2;
  input A3;
  output ZN;
  assign ZN = ~((A1 & A2) & A3);
endmodule
module NAND3_X2 (A1, A2, A3, ZN);
  input A1;
  input A2;
  input A3;
  output ZN;
  assign ZN = ~((A1 & A2) & A3);
endmodule
module NAND3_X4 (A1, A2, A3, ZN);
  input A1;
  input A2;
  input A3;
  output ZN;
  assign ZN = ~((A1 & A2) & A3);
endmodule
module NAND4_X1 (A1, A2, A3, A4, ZN);
  input A1;
  input A2;
  input A3;
  input A4;
  output ZN;
  assign ZN = ~(((A1 & A2) & A3) & A4);
endmodule
module NAND4_X2 (A1, A2, A3, A4, ZN);
  input A1;
  input A2;
  input A3;
  input A4;
  output ZN;
  assign ZN = ~(((A1 & A2) & A3) & A4);
endmodule
module NAND4_X4 (A1, A2, A3, A4, ZN);
  input A1;
  input A2;
  input A3;
  input A4;
  output ZN;
  assign ZN = ~(((A1 & A2) & A3) & A4);
endmodule
module NOR2_X1 (A1, A2, ZN);
  input A1;
  input A2;
  output ZN;
  assign ZN = ~(A1 | A2);
endmodule
module NOR2_X2 (A1, A2, ZN);
  input A1;
  input A2;
  output ZN;
  assign ZN = ~(A1 | A2);
endmodule
module NOR2_X4 (A1, A2, ZN);
  input A1;
  input A2;
  output ZN;
  assign ZN = ~(A1 | A2);
endmodule
module NOR3_X1 (A1, A2, A3, ZN);
  input A1;
  input A2;
  input A3;
  output ZN;
  assign ZN = ~((A1 | A2) | A3);
endmodule
module NOR3_X2 (A1, A2, A3, ZN);
  input A1;
  input A2;
  input A3;
  output ZN;
  assign ZN = ~((A1 | A2) | A3);
endmodule
module NOR3_X4 (A1, A2, A3, ZN);
  input A1;
  input A2;
  input A3;
  output ZN;
  assign ZN = ~((A1 | A2) | A3);
endmodule
module NOR4_X1 (A1, A2, A3, A4, ZN);
  input A1;
  input A2;
  input A3;
  input A4;
  output ZN;
  assign ZN = ~(((A1 | A2) | A3) | A4);
endmodule
module NOR4_X2 (A1, A2, A3, A4, ZN);
  input A1;
  input A2;
  input A3;
  input A4;
  output ZN;
  assign ZN = ~(((A1 | A2) | A3) | A4);
endmodule
module NOR4_X4 (A1, A2, A3, A4, ZN);
  input A1;
  input A2;
  input A3;
  input A4;
  output ZN;
  assign ZN = ~(((A1 | A2) | A3) | A4);
endmodule
module OAI21_X1 (A, B1, B2, ZN);
  input A;
  input B1;
  input B2;
  output ZN;
  assign ZN = ~(A & (B1 | B2));
endmodule
module OAI21_X2 (A, B1, B2, ZN);
  input A;
  input B1;
  input B2;
  output ZN;
  assign ZN = ~(A & (B1 | B2));
endmodule
module OAI21_X4 (A, B1, B2, ZN);
  input A;
  input B1;
  input B2;
  output ZN;
  assign ZN = ~(A & (B1 | B2));
endmodule
module OAI22_X1 (A1, A2, B1, B2, ZN);
  input A1;
  input A2;
  input B1;
  input B2;
  output ZN;
  assign ZN = ~((A1 | A2) & (B1 | B2));
endmodule
module OAI22_X2 (A1, A2, B1, B2, ZN);
  input A1;
  input A2;
  input B1;
  input B2;
  output ZN;
  assign ZN = ~((A1 | A2) & (B1 | B2));
endmodule
module OAI22_X4 (A1, A2, B1, B2, ZN);
  input A1;
  input A2;
  input B1;
  input B2;
  output ZN;
  assign ZN = ~((A1 | A2) & (B1 | B2));
endmodule
module OAI33_X1 (A1, A2, A3, B1, B2, B3, ZN);
  input A1;
  input A2;
  input A3;
  input B1;
  input B2;
  input B3;
  output ZN;
  assign ZN = ~(((A1 | A2) | A3) & ((B1 | B2) | B3));
endmodule
module OAI211_X1 (A, B, C1, C2, ZN);
  input A;
  input B;
  input C1;
  input C2;
  output ZN;
  assign ZN = ~(((C1 | C2) & A) & B);
endmodule
module OAI211_X2 (A, B, C1, C2, ZN);
  input A;
  input B;
  input C1;
  input C2;
  output ZN;
  assign ZN = ~(((C1 | C2) & A) & B);
endmodule
module OAI211_X4 (A, B, C1, C2, ZN);
  input A;
  input B;
  input C1;
  input C2;
  output ZN;
  assign ZN = ~(((C1 | C2) & A) & B);
endmodule
module OAI221_X1 (A, B1, B2, C1, C2, ZN);
  input A;
  input B1;
  input B2;
  input C1;
  input C2;
  output ZN;
  assign ZN = ~(((C1 | C2) & A) & (B1 | B2));
endmodule
module OAI221_X2 (A, B1, B2, C1, C2, ZN);
  input A;
  input B1;
  input B2;
  input C1;
  input C2;
  output ZN;
  assign ZN = ~(((C1 | C2) & A) & (B1 | B2));
endmodule
module OAI221_X4 (A, B1, B2, C1, C2, ZN);
  input A;
  input B1;
  input B2;
  input C1;
  input C2;
  output ZN;
  assign ZN = ~(~(~(((C1 | C2) & A) & (B1 | B2))));
endmodule
module OAI222_X1 (A1, A2, B1, B2, C1, C2, ZN);
  input A1;
  input A2;
  input B1;
  input B2;
  input C1;
  input C2;
  output ZN;
  assign ZN = ~(((A1 | A2) & (B1 | B2)) & (C1 | C2));
endmodule
module OAI222_X2 (A1, A2, B1, B2, C1, C2, ZN);
  input A1;
  input A2;
  input B1;
  input B2;
  input C1;
  input C2;
  output ZN;
  assign ZN = ~(((A1 | A2) & (B1 | B2)) & (C1 | C2));
endmodule
module OAI222_X4 (A1, A2, B1, B2, C1, C2, ZN);
  input A1;
  input A2;
  input B1;
  input B2;
  input C1;
  input C2;
  output ZN;
  assign ZN = ~(~(~(((A1 | A2) & (B1 | B2)) & (C1 | C2))));
endmodule
module OR2_X1 (A1, A2, ZN);
  input A1;
  input A2;
  output ZN;
  assign ZN = (A1 | A2);
endmodule
module OR2_X2 (A1, A2, ZN);
  input A1;
  input A2;
  output ZN;
  assign ZN = (A1 | A2);
endmodule
module OR2_X4 (A1, A2, ZN);
  input A1;
  input A2;
  output ZN;
  assign ZN = (A1 | A2);
endmodule
module OR3_X1 (A1, A2, A3, ZN);
  input A1;
  input A2;
  input A3;
  output ZN;
  assign ZN = ((A1 | A2) | A3);
endmodule
module OR3_X2 (A1, A2, A3, ZN);
  input A1;
  input A2;
  input A3;
  output ZN;
  assign ZN = ((A1 | A2) | A3);
endmodule
module OR3_X4 (A1, A2, A3, ZN);
  input A1;
  input A2;
  input A3;
  output ZN;
  assign ZN = ((A1 | A2) | A3);
endmodule
module OR4_X1 (A1, A2, A3, A4, ZN);
  input A1;
  input A2;
  input A3;
  input A4;
  output ZN;
  assign ZN = (((A1 | A2) | A3) | A4);
endmodule
module OR4_X2 (A1, A2, A3, A4, ZN);
  input A1;
  input A2;
  input A3;
  input A4;
  output ZN;
  assign ZN = (((A1 | A2) | A3) | A4);
endmodule
module OR4_X4 (A1, A2, A3, A4, ZN);
  input A1;
  input A2;
  input A3;
  input A4;
  output ZN;
  assign ZN = (((A1 | A2) | A3) | A4);
endmodule
module SDFFRS_X1 (D, RN, SE, SI, SN, CK, Q, QN);
  input D;
  input RN;
  input SE;
  input SI;
  input SN;
  input CK;
  output Q;
  output QN;
  reg IQ = 1'b0;
  wire IQN = ~IQ;
  wire ck_ = CK;
  always @(posedge ck_ or posedge (~RN) or posedge (~SN))
    if (~RN) IQ <= 1'b0; else if (~SN) IQ <= 1'b1; else IQ <= ((SE & SI) | (D & ~SE));
  assign Q = IQ;
  assign QN = IQN;
endmodule
module SDFFRS_X2 (D, RN, SE, SI, SN, CK, Q, QN);
  input D;
  input RN;
  input SE;
  input SI;
  input SN;
  input CK;
  output Q;
  output QN;
  reg IQ = 1'b0;
  wire IQN = ~IQ;
  wire ck_ = CK;
  always @(posedge ck_ or posedge (~RN) or posedge (~SN))
    if (~RN) IQ <= 1'b0; else if (~SN) IQ <= 1'b1; else IQ <= ((SE & SI) | (D & ~SE));
  assign Q = IQ;
  assign QN = IQN;
endmodule
module SDFFR_X1 (D, RN, SE, SI, CK, Q, QN);
  input D;
  input RN;
  input SE;
  input SI;
  input CK;
  output Q;
  output QN;
  reg IQ = 1'b0;
  wire IQN = ~IQ;
  wire ck_ = CK;
  always @(posedge ck_ or posedge (~RN) or posedge (1'b0))
    if (~RN) IQ <= 1'b0; else if (1'b0) IQ <= 1'b1; else IQ <= ((SE & SI) | (D & ~SE));
  assign Q = IQ;
  assign QN = IQN;
endmodule
module SDFFR_X2 (D, RN, SE, SI, CK, Q, QN);
  input D;
  input RN;
  input SE;
  input SI;
  input CK;
  output Q;
  output QN;
  reg IQ = 1'b0;
  wire IQN = ~IQ;
  wire ck_ = CK;
  always @(posedge ck_ or posedge (~RN) or posedge (1'b0))
    if (~RN) IQ <= 1'b0; else if (1'b0) IQ <= 1'b1; else IQ <= ((SE & SI) | (D & ~SE));
  assign Q = IQ;
  assign QN = IQN;
endmodule
module SDFFS_X1 (D, SE, SI, SN, CK, Q, QN);
  input D;
  input SE;
  input SI;
  input SN;
  input CK;
  output Q;
  output QN;
  reg IQ = 1'b0;
  wire IQN = ~IQ;
  wire ck_ = CK;
  always @(posedge ck_ or posedge (1'b0) or posedge (~SN))
    if (1'b0) IQ <= 1'b0; else if (~SN) IQ <= 1'b1; else IQ <= ((SE & SI) | (D & ~SE));
  assign Q = IQ;
  assign QN = IQN;
endmodule
module SDFFS_X2 (D, SE, SI, SN, CK, Q, QN);
  input D;
  input SE;
  input SI;
  input SN;
  input CK;
  output Q;
  output QN;
  reg IQ = 1'b0;
  wire IQN = ~IQ;
  wire ck_ = CK;
  always @(posedge ck_ or posedge (1'b0) or posedge (~SN))
    if (1'b0) IQ <= 1'b0; else if (~SN) IQ <= 1'b1; else IQ <= ((SE & SI) | (D & ~SE));
  assign Q = IQ;
  assign QN = IQN;
endmodule
module SDFF_X1 (D, SE, SI, CK, Q, QN);
  input D;
  input SE;
  input SI;
  input CK;
  output Q;
  output QN;
  reg IQ = 1'b0;
  wire IQN = ~IQ;
  wire ck_ = CK;
  always @(posedge ck_) IQ <= ((SE & SI) | (D & ~SE));
  assign Q = IQ;
  assign QN = IQN;
endmodule
module SDFF_X2 (D, SE, SI, CK, Q, QN);
  input D;
  input SE;
  input SI;
  input CK;
  output Q;
  output QN;
  reg IQ = 1'b0;
  wire IQN = ~IQ;
  wire ck_ = CK;
  always @(posedge ck_) IQ <= ((SE & SI) | (D & ~SE));
  assign Q = IQ;
  assign QN = IQN;
endmodule
module TBUF_X1 (A, EN, Z);
  input A;
  input EN;
  output Z;
  assign Z = A;
endmodule
module TBUF_X2 (A, EN, Z);
  input A;
  input EN;
  output Z;
  assign Z = A;
endmodule
module TBUF_X4 (A, EN, Z);
  input A;
  input EN;
  output Z;
  assign Z = A;
endmodule
module TBUF_X8 (A, EN, Z);
  input A;
  input EN;
  output Z;
  assign Z = A;
endmodule
module TBUF_X16 (A, EN, Z);
  input A;
  input EN;
  output Z;
  assign Z = A;
endmodule
module TINV_X1 (EN, I, ZN);
  input EN;
  input I;
  output ZN;
  assign ZN = ~I;
endmodule
module TLAT_X1 (D, G, OE, Q);
  input D;
  input G;
  input OE;
  output Q;
  reg IQ = 1'b0;
  wire IQN = ~IQ;
  always @* if (G) IQ = D;
  assign Q = IQ;
endmodule
module XNOR2_X1 (A, B, ZN);
  input A;
  input B;
  output ZN;
  assign ZN = ~(A ^ B);
endmodule
module XNOR2_X2 (A, B, ZN);
  input A;
  input B;
  output ZN;
  assign ZN = ~(A ^ B);
endmodule
module XOR2_X1 (A, B, Z);
  input A;
  input B;
  output Z;
  assign Z = (A ^ B);
endmodule
module XOR2_X2 (A, B, Z);
  input A;
  input B;
  output Z;
  assign Z = (A ^ B);
endmodule

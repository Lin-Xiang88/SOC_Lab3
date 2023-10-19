`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/11/2023 10:15:12 PM
// Design Name: 
// Module Name: fir
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module fir 
#(  parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32,
    parameter Tape_Num    = 11
)
(
    output  reg                     awready,
    output  reg                     wready,
    input   wire                     awvalid,
    input   wire [(pADDR_WIDTH-1):0] awaddr,
    input   wire                     wvalid,
    input   wire [(pDATA_WIDTH-1):0] wdata,
    output  reg                     arready,
    input   wire                     rready,
    input   wire                     arvalid,
    input   wire [(pADDR_WIDTH-1):0] araddr,
    output  reg                     rvalid,
    output  wire [(pDATA_WIDTH-1):0] rdata,    
    input   wire                     ss_tvalid, 
    input   wire [(pDATA_WIDTH-1):0] ss_tdata, 
    input   wire                     ss_tlast, 
    output  reg                     ss_tready, 
    input   wire                     sm_tready, 
    output  reg                     sm_tvalid, 
    output  reg [(pDATA_WIDTH-1):0] sm_tdata, 
    output  reg                     sm_tlast, 
    
    // bram for tap RAM
    output  reg [3:0]               tap_WE,
    output  reg                     tap_EN,
    output  reg [(pDATA_WIDTH-1):0] tap_Di,
    output  reg [(pADDR_WIDTH-1):0] tap_A,
    input   wire [(pDATA_WIDTH-1):0] tap_Do,

    // bram for data RAM
    output  reg [3:0]               data_WE,
    output  reg                     data_EN,
    output  reg [(pDATA_WIDTH-1):0] data_Di,
    output  reg [(pADDR_WIDTH-1):0] data_A,
    input   wire [(pDATA_WIDTH-1):0] data_Do,

    input   wire                     axis_clk,
    input   wire                     axis_rst_n
);


    // write your code here!
//state
parameter idle          =   3'b000;
parameter rst_dataram   =   3'b001;
parameter rd_ss         =   3'b010;
parameter ConV          =   3'b011;
parameter wr_sm         =   3'b100;
parameter ap_done       =   3'b101;
parameter ap_idle       =   3'b110;     

reg [6:0]cnt;
reg [3:0]tap_cnt;
reg [2:0]cur_state;
reg [31:0]p_cnt;
reg [31:0]temp;
reg [3:0]conv_cnt;

always@(posedge axis_clk,negedge axis_rst_n)begin
  if(!axis_rst_n)begin
    cur_state<=0;
  end
  else begin
    case(cur_state)  
      idle:begin
        if(wdata==32'h0000_0001)cur_state<=rst_dataram;
        else    cur_state<=idle;
      end
      rst_dataram:begin
        if(data_A==40)cur_state<=rd_ss;
        else cur_state<=rst_dataram;
      end
      rd_ss:begin
        if(sm_tlast) cur_state<=ap_done;
        else cur_state<=ConV;
      end  
      ConV:begin
        if(conv_cnt==11)cur_state<=wr_sm;
        else cur_state<=ConV;  
      end  
      wr_sm:
        cur_state<=rd_ss;       
      ap_done:begin
        if(arvalid&araddr==12'h00&rvalid&rdata==32'h02) cur_state<=ap_idle;
        else cur_state<=ap_done;
      end
      ap_idle:
        cur_state<=ap_idle;
      default:
          cur_state<=idle;
    endcase    
  end
end

//=======================================================
//aw&w
always@(posedge axis_clk,negedge axis_rst_n)begin
  if(~axis_rst_n)begin
    awready<=0;
    wready<=0;
  end
  else begin
    if(awvalid)begin
      awready<=1;
      wready<=1;
    end
    else begin
      awready<=0;
      wready<=0;
    end  
  end
end
//=======================================================
//ar&r
always@(posedge axis_clk,negedge axis_rst_n)begin
  if(!axis_rst_n)begin
    arready<=1;
  end
  else begin
    if(arvalid)
      arready<=0;
    else
      arready<=1;
  end
end

always@(posedge axis_clk,negedge axis_rst_n)begin
  if(!axis_rst_n)
    rvalid<=0;
  else begin
    if((arvalid)&(!arready))
      rvalid<=1;
    else 
      rvalid<=0;         
  end
end

assign rdata = (arvalid&araddr==12'd0) ? 
               ((cur_state==ap_done) ? 32'h2 : (cur_state==ap_idle ? 32'h04:32'h00))
               :((arvalid) ? tap_Do : rdata);
//=======================================================
//coef write to tap_ram  
always@(posedge axis_clk,negedge axis_rst_n)begin
  if(!axis_rst_n)begin
    tap_WE<=0;
    tap_EN<=0;
    tap_Di<=0;
    tap_A<=0;
    tap_cnt<=0;
  end
  else begin
    if(cur_state==ConV)begin
      tap_WE<=4'b0000;
      tap_EN<=1;
      tap_A<=cnt;    
    end
    else if(awvalid&awready&tap_cnt<12)begin
      tap_WE<=4'b1111;
      tap_EN<=1;
      tap_A<={5'd0,awaddr[6],awaddr[4:0]};
      tap_cnt<=tap_cnt+1;    
    end
    else if(arvalid&arready)begin
      tap_EN<=1;
      tap_A<={5'd0,araddr[6],araddr[4:0]};    
    end
    else begin
      tap_WE<=4'b0000;
      tap_EN<=1;
      tap_A<=tap_A;          
    end
    
    if(wvalid&wready)
        tap_Di<=wdata;
    else
        tap_Di<=tap_Di;
  end
end
//=======================================================
//ss
always@(posedge axis_clk,negedge axis_rst_n)begin
  if(!axis_rst_n)begin
    ss_tready<=0;
 
  end
  else begin
    if(ss_tvalid&cur_state==rd_ss)begin
      ss_tready<=1;
   
    end  
    else begin 
      ss_tready<=0;         
      
    end
  end
end
//=======================================================
//sm
always@(posedge axis_clk,negedge axis_rst_n)begin
  if(!axis_rst_n)
    sm_tvalid<=0;
  else begin
    if(cur_state==wr_sm)
      sm_tvalid<=1;
    else
      sm_tvalid<=0;         
  end
end

always@(posedge axis_clk,negedge axis_rst_n)begin
  if(!axis_rst_n)begin
    cnt<=0;
    temp<=0;
    conv_cnt<=0;
  end  
  else begin
    if(cur_state==ConV)begin
      temp<=data_Do*tap_Do+temp;
      conv_cnt<=conv_cnt+1;
      if(cnt==40)
        cnt<=cnt;
      else  
        cnt<=cnt+4;
    end  
    else if(cur_state==rd_ss)begin
      temp<=0;
      conv_cnt<=0;
    end
    else begin
      cnt<=0;
      temp=temp;  
      conv_cnt<=conv_cnt;       
    end
  end
end

//assign sm_tdata=temp;
always@(posedge axis_clk,negedge axis_rst_n)begin
  if(!axis_rst_n)begin
    sm_tdata<=0;
  end  
  else begin
    if(cur_state==wr_sm)begin
      sm_tdata<=temp;
    end  
    else begin
      sm_tdata<=sm_tdata;         
    end
  end
end

always@(posedge axis_clk,negedge axis_rst_n)begin
  if(!axis_rst_n)
    sm_tlast<=0;
  else begin
    if(cur_state==wr_sm&p_cnt==599)
      sm_tlast<=1;
    else
      sm_tlast<=sm_tlast;         
  end
end

always@(posedge axis_clk,negedge axis_rst_n)begin
  if(!axis_rst_n)
    p_cnt<=0;
  else begin
    if(cur_state==wr_sm)
      p_cnt<=p_cnt+1;
    else
      p_cnt<=p_cnt;        
  end
end
//=======================================================
//data_ram write
reg [11:0]head_cnt;

always@(posedge axis_clk,negedge axis_rst_n)begin
  if(!axis_rst_n)
    head_cnt<=12'hffc;
  else begin
    if(cur_state==rd_ss)
      if(head_cnt==12'd40)
        head_cnt<=0;   
      else
        head_cnt<=head_cnt+4;  
    else 
      head_cnt<=head_cnt;         
  end
end

always@(posedge axis_clk,negedge axis_rst_n)begin
  if(!axis_rst_n)begin
    data_WE<=0;
    data_EN<=0;
    data_Di<=0;
    data_A<=0;
  end
  else begin
    if(cur_state==rst_dataram)begin
      data_WE<=4'b1111;
      data_EN<=1;
      data_Di<=0;
      if(data_A<40)data_A<=data_A+4;      
      else data_A<=data_A;  
    end
    else if(cur_state==rd_ss)begin
      data_WE<=4'b1111;
      data_EN<=1;
      data_Di<=ss_tdata;
      if(head_cnt==40)
        data_A<=0;
      else
      data_A<=head_cnt+4; 
    end
    else if(cur_state==ConV)begin
      data_WE<=4'b0000;
      data_EN<=1;
      if(head_cnt<cnt)
        data_A<=head_cnt+44-cnt;
      else  
        data_A<=head_cnt-cnt;
    end    
    else begin
      data_WE<=4'b0000;
      data_EN<=1;
      data_Di<=data_Di;
      data_A<=data_A;       
    end
  end
end

endmodule

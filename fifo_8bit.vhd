library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fifo_8bit is
    generic (
        DEPTH : integer := 300
    );
    port (
        clk      : in  std_logic;
        rst      : in  std_logic;
        din      : in  std_logic_vector(7 downto 0);
        wr_en    : in  std_logic;
        rd_en    : in  std_logic;
        dout     : out std_logic_vector(7 downto 0);
        full     : out std_logic;
        empty    : out std_logic;
        count    : out integer range 0 to DEPTH
    );
end entity fifo_8bit;

architecture rtl of fifo_8bit is
    type memory_array is array(0 to DEPTH-1) of std_logic_vector(7 downto 0);
    signal memory : memory_array;
    signal wr_ptr : integer range 0 to DEPTH-1;
    signal rd_ptr : integer range 0 to DEPTH-1;
    signal cnt    : integer range 0 to DEPTH;
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                wr_ptr <= 0;
                rd_ptr <= 0;
                cnt    <= 0;
            else
                -- Write operation
                if wr_en = '1' and cnt < DEPTH then
                    memory(wr_ptr) <= din;
                    if wr_ptr = DEPTH-1 then
                        wr_ptr <= 0;
                    else
                        wr_ptr <= wr_ptr + 1;
                    end if;
                    cnt <= cnt + 1;
                end if;
                
                -- Read operation
                if rd_en = '1' and cnt > 0 then
                    if rd_ptr = DEPTH-1 then
                        rd_ptr <= 0;
                    else
                        rd_ptr <= rd_ptr + 1;
                    end if;
                    cnt <= cnt - 1;
                end if;
            end if;
        end if;
    end process;
    
    dout  <= memory(rd_ptr);
    full  <= '1' when cnt = DEPTH else '0';
    empty <= '1' when cnt = 0 else '0';
    count <= cnt;
end architecture rtl;

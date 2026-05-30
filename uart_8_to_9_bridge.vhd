library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_8_to_9_bridge is
    generic (
        -- Input RX parameters (from 100 MHz clock)
        RX_BAUD_RATE : integer := 115200;      -- RX baud rate in Hz
        RX_CLOCK_FREQ : integer := 100_000_000; -- Input clock frequency in Hz
        
        -- Output TX parameters
        TX_BAUD_RATE : integer := 115200;       -- TX baud rate in Hz
        TX_CLOCK_FREQ : integer := 100_000_000; -- TX clock frequency (same as input)
        
        -- FIFO parameters
        FIFO_DEPTH : integer := 300             -- Number of 8-bit frames to store
    );
    port (
        clk      : in  std_logic;                -- 100 MHz input clock
        rst      : in  std_logic;                -- Active high reset
        uart_rx  : in  std_logic;                -- UART RX input (idle high)
        uart_tx  : out std_logic                 -- UART TX output (idle high)
    );
end entity uart_8_to_9_bridge;

architecture rtl of uart_8_to_9_bridge is

    -- =========================================================================
    -- Component Declarations
    -- =========================================================================
    
    component fifo_8bit is
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
    end component fifo_8bit;

    -- =========================================================================
    -- RX Module (UART 8-bit Receiver at 100MHz, 1:1 clock)
    -- =========================================================================
    
    -- RX control signals
    signal rx_baud_cnt      : integer range 0 to RX_CLOCK_FREQ / RX_BAUD_RATE;
    signal rx_bit_cnt       : integer range 0 to 10;
    signal rx_data          : std_logic_vector(7 downto 0);
    signal rx_data_valid    : std_logic;
    signal rx_busy          : std_logic;
    
    -- Synchronizers for RX input
    signal uart_rx_sync1    : std_logic;
    signal uart_rx_sync2    : std_logic;
    signal uart_rx_prev     : std_logic;
    
    -- =========================================================================
    -- FIFO Signals
    -- =========================================================================
    
    signal fifo_din         : std_logic_vector(7 downto 0);
    signal fifo_wr_en       : std_logic;
    signal fifo_rd_en       : std_logic;
    signal fifo_dout        : std_logic_vector(7 downto 0);
    signal fifo_full        : std_logic;
    signal fifo_empty       : std_logic;
    signal fifo_count       : integer range 0 to FIFO_DEPTH;
    
    -- =========================================================================
    -- TX Module (UART 9-bit Transmitter at configurable baud rate)
    -- =========================================================================
    
    -- TX control signals
    signal tx_baud_cnt      : integer range 0 to TX_CLOCK_FREQ / TX_BAUD_RATE;
    signal tx_bit_cnt       : integer range 0 to 11;  -- 0=start, 1-8=data, 9=9th bit, 10=stop
    signal tx_data          : std_logic_vector(7 downto 0);
    signal tx_busy          : std_logic;
    signal tx_bit_out       : std_logic;
    signal tx_frame_cnt     : integer range 0 to FIFO_DEPTH;
    
begin

    -- =========================================================================
    -- RX Module: 8-bit UART Receiver
    -- =========================================================================
    -- Receives 8-bit frames at configurable baud rate with 1:1 clock division
    -- Detects falling edge on RX line and samples bits at 1/2 baud offset
    
    process(clk) is
        variable temp_data : std_logic_vector(7 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                uart_rx_sync1   <= '1';
                uart_rx_sync2   <= '1';
                uart_rx_prev    <= '1';
                rx_baud_cnt     <= 0;
                rx_bit_cnt      <= 0;
                rx_data         <= (others => '0');
                rx_data_valid   <= '0';
                rx_busy         <= '0';
                temp_data       := (others => '0');
            else
                -- Synchronize RX input (2 FF chain for metastability)
                uart_rx_sync1   <= uart_rx;
                uart_rx_sync2   <= uart_rx_sync1;
                rx_data_valid   <= '0';
                
                if rx_busy = '0' then
                    -- Waiting for start bit (falling edge)
                    uart_rx_prev <= uart_rx_sync2;
                    
                    if uart_rx_prev = '1' and uart_rx_sync2 = '0' then
                        -- Falling edge detected - start bit
                        rx_busy     <= '1';
                        rx_baud_cnt <= RX_CLOCK_FREQ / (2 * RX_BAUD_RATE); -- 1/2 baud offset
                        rx_bit_cnt  <= 0;
                        temp_data   := (others => '0');
                    end if;
                else
                    -- We are receiving a frame
                    if rx_baud_cnt = 0 then
                        -- Time to sample a bit
                        if rx_bit_cnt = 0 then
                            -- Sample start bit (should be 0)
                            rx_bit_cnt <= 1;
                        elsif rx_bit_cnt < 9 then
                            -- Sample data bits (1-8)
                            temp_data(rx_bit_cnt - 1) := uart_rx_sync2;
                            rx_bit_cnt <= rx_bit_cnt + 1;
                        else
                            -- Sample stop bit (should be 1)
                            rx_data       <= temp_data;
                            rx_data_valid <= '1';
                            rx_busy       <= '0';
                            rx_bit_cnt    <= 0;
                        end if;
                        
                        -- Reload baud counter for next sample
                        if rx_bit_cnt < 9 then
                            rx_baud_cnt <= RX_CLOCK_FREQ / RX_BAUD_RATE - 1;
                        else
                            rx_baud_cnt <= 0;
                        end if;
                    else
                        -- Count down to next sample
                        rx_baud_cnt <= rx_baud_cnt - 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- =========================================================================
    -- FIFO: 8-bit x 300 frame buffer
    -- =========================================================================
    
    fifo_wr_en <= rx_data_valid;
    fifo_din   <= rx_data;
    
    fifo_inst : fifo_8bit
        generic map (
            DEPTH => FIFO_DEPTH
        )
        port map (
            clk      => clk,
            rst      => rst,
            din      => fifo_din,
            wr_en    => fifo_wr_en,
            rd_en    => fifo_rd_en,
            dout     => fifo_dout,
            full     => fifo_full,
            empty    => fifo_empty,
            count    => fifo_count
        );

    -- =========================================================================
    -- TX Module: 9-bit UART Transmitter
    -- =========================================================================
    -- Transmits frames from FIFO with injected 9th bit
    -- 9th bit = 1 for first frame, 0 for all subsequent frames
    
    process(clk) is
    begin
        if rising_edge(clk) then
            if rst = '1' then
                tx_baud_cnt     <= 0;
                tx_bit_cnt      <= 0;
                tx_data         <= (others => '0');
                tx_busy         <= '0';
                tx_bit_out      <= '1';
                tx_frame_cnt    <= 0;
                fifo_rd_en      <= '0';
            else
                fifo_rd_en <= '0';
                
                if tx_busy = '0' then
                    -- Not currently transmitting
                    if fifo_empty = '0' then
                        -- Data available in FIFO - start transmission
                        tx_busy     <= '1';
                        tx_baud_cnt <= TX_CLOCK_FREQ / TX_BAUD_RATE - 1;
                        tx_bit_cnt  <= 0;
                        tx_bit_out  <= '0';  -- Start bit
                        fifo_rd_en  <= '1';
                        tx_data     <= fifo_dout;  -- Capture data immediately
                        tx_frame_cnt <= tx_frame_cnt + 1;
                    else
                        tx_bit_out <= '1';  -- Keep idle high
                    end if;
                else
                    -- Currently transmitting - count down baud timer
                    if tx_baud_cnt = 0 then
                        -- Time to transition to next bit
                        tx_bit_cnt <= tx_bit_cnt + 1;
                        
                        -- Set next bit value and reload baud counter
                        case tx_bit_cnt is
                            when 0 =>
                                -- Just sent start bit, now send data bit 0
                                tx_bit_out  <= tx_data(0);
                                tx_baud_cnt <= TX_CLOCK_FREQ / TX_BAUD_RATE - 1;
                            when 1 =>
                                tx_bit_out  <= tx_data(1);
                                tx_baud_cnt <= TX_CLOCK_FREQ / TX_BAUD_RATE - 1;
                            when 2 =>
                                tx_bit_out  <= tx_data(2);
                                tx_baud_cnt <= TX_CLOCK_FREQ / TX_BAUD_RATE - 1;
                            when 3 =>
                                tx_bit_out  <= tx_data(3);
                                tx_baud_cnt <= TX_CLOCK_FREQ / TX_BAUD_RATE - 1;
                            when 4 =>
                                tx_bit_out  <= tx_data(4);
                                tx_baud_cnt <= TX_CLOCK_FREQ / TX_BAUD_RATE - 1;
                            when 5 =>
                                tx_bit_out  <= tx_data(5);
                                tx_baud_cnt <= TX_CLOCK_FREQ / TX_BAUD_RATE - 1;
                            when 6 =>
                                tx_bit_out  <= tx_data(6);
                                tx_baud_cnt <= TX_CLOCK_FREQ / TX_BAUD_RATE - 1;
                            when 7 =>
                                tx_bit_out  <= tx_data(7);
                                tx_baud_cnt <= TX_CLOCK_FREQ / TX_BAUD_RATE - 1;
                            when 8 =>
                                -- 9th bit injection
                                if tx_frame_cnt = 1 then
                                    tx_bit_out <= '1';
                                else
                                    tx_bit_out <= '0';
                                end if;
                                tx_baud_cnt <= TX_CLOCK_FREQ / TX_BAUD_RATE - 1;
                            when 9 =>
                                -- Stop bit
                                tx_bit_out  <= '1';
                                tx_baud_cnt <= TX_CLOCK_FREQ / TX_BAUD_RATE - 1;
                            when 10 =>
                                -- Frame complete
                                tx_busy     <= '0';
                                tx_bit_cnt  <= 0;
                                tx_bit_out  <= '1';  -- Return to idle
                                
                                -- Check if FIFO is now empty
                                if fifo_empty = '1' then
                                    -- Reset for next transmission session
                                    tx_frame_cnt <= 0;
                                end if;
                            when others =>
                                null;
                        end case;
                    else
                        -- Count down baud timer
                        tx_baud_cnt <= tx_baud_cnt - 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Output TX signal
    uart_tx <= tx_bit_out;

end architecture rtl;

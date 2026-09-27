library IEEE;
use IEEE.numeric_std.all;
use IEEE.std_logic_1164.all;

entity three_k_plus_one is
    port(
        reset : in std_logic;
        clk_in : in std_logic;
        an : out std_logic_vector(7 downto 0);
        sseg : out std_logic_vector(7 downto 0);
        done_out : out std_logic
    );
end three_k_plus_one;

architecture rtl of three_k_plus_one is

    -- Internal slow clock for the 3k+1 procedure (1Hz)
    signal clk : std_logic;
    constant CLK_DIV_MAX : integer := 49999999; -- use 1 for simulation
    signal clk_count : integer range 0 to CLK_DIV_MAX;

    -- Signals for 3k+1 logic
    signal number_out : unsigned(6 downto 0);
    signal term_out : unsigned(6 downto 0);
    signal length : unsigned(3 downto 0);
    signal done : std_logic;

    -- Signals for 7-segment display refresh
    constant N : integer := 18; -- use 4 for simulation
    signal q_reg, q_next : unsigned(N-1 downto 0);
    signal sel : std_logic_vector(1 downto 0);
    signal current_digit : std_logic_vector(3 downto 0);

    -- Signals for BCD conversion
    signal term_tens : std_logic_vector(3 downto 0);
    signal term_ones : std_logic_vector(3 downto 0);
    signal number_bcd : std_logic_vector(3 downto 0);
begin
    -- Slow clock from 100 MHz board clock to 1Hz
    clock_divider: process(clk_in, reset)
    begin
        if reset = '1' then
            clk <= '0';
            clk_count <= 0;
        elsif (clk_in'event and clk_in = '1') then
            if clk_count = CLK_DIV_MAX then
                clk_count <= 0;
                clk <= not clk;
            else
                clk_count <= clk_count + 1;
            end if;
        end if;
    end process;

    -- 7-segment display refresh counter
    display_counter: process(clk_in, reset)
    begin
        if reset = '1' then
            q_reg <= (others => '0');
        elsif (clk_in'event and clk_in = '1') then
            q_reg <= q_next;
        end if;
    end process;
    q_next <= q_reg + 1;

    -- Main 3k+1 algorithm in a single process
    three_k_logic: process(clk, reset)
    begin
        if reset = '1' then
            number_out <= "0000001";
            term_out <= "0000001";
            length <= "0001";
            done <= '0';
        elsif (clk'event and clk = '1') then
            if done = '0' then
                if length >= "1001" then
                    done <= '1';
                elsif term_out = "0000001" then
                    number_out <= number_out + 1;
                    term_out <= number_out + 1;
                    length <= "0001";
                else
                    if term_out(0) = '0' then --even
                        term_out <= '0' & term_out(6 downto 1);
                    else --odd
                        term_out <= resize(term_out * 3 + 1, 7);
                    end if;
                    length <= length + 1;
                end if;
            end if;
        end if;
    end process;
    done_out <= done;

    -- Convert term_out from binary to two BCD digits
    bcd_converter: process(term_out)
        variable temp : unsigned(6 downto 0);
        variable tens : unsigned(3 downto 0);
    begin
        temp := term_out;
        tens := "0000";
        for i in 0 to 9 loop
            if temp >= "0001010" then
                temp := temp - 10;
                tens := tens + 1;
            end if;
        end loop;
        term_tens <= std_logic_vector(tens);
        term_ones <= std_logic_vector(temp(3 downto 0));
    end process;
    number_bcd <= std_logic_vector(number_out(3 downto 0));

    -- Use top two counter bits to select the active display digit
    sel <= std_logic_vector(q_reg(N-1 downto N-2));

    -- 7-segment display mux
    display_mux: process(sel, term_ones, term_tens, number_bcd)
    begin
        an <= "11111111";
        current_digit <= "0000";
        case sel is
            when "00" =>
                an <= "11111110";
                current_digit <= term_ones;
            when "01" =>
                an <= "11111101";
                current_digit <= term_tens;
            when "10" =>
                an <= "11111011";
                current_digit <= number_bcd;
            when others =>
                an <= "11111111";
                current_digit <= "0000";
        end case;
    end process;

    -- BCD digit to 7-segment decoder
    with current_digit select
        sseg(7 downto 1) <=
            "0000001" when "0000", -- 0
            "1001111" when "0001", -- 1
            "0010010" when "0010", -- 2
            "0000110" when "0011", -- 3
            "1001100" when "0100", -- 4
            "0100100" when "0101", -- 5
            "0100000" when "0110", -- 6
            "0001111" when "0111", -- 7
            "0000000" when "1000", -- 8
            "0000100" when "1001", -- 9
            "1111111" when others; -- blank

    -- Decimal point off
    sseg(0) <= '1';
end rtl;

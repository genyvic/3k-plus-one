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

    -- Internal slow clock for the 3k+1 procedure
    signal clk : std_logic;
    constant CLK_DIV_MAX : integer := 49999999; -- use 1 for simulation
    signal clk_count : integer range 0 to CLK_DIV_MAX;

    -- Signals for the 3k+1 algorithm
    signal number_out : unsigned(6 downto 0);
    signal term_out : unsigned(6 downto 0);
    signal length : unsigned(3 downto 0);
    signal done : std_logic;

    -- ASM states
    type state_type is (
        reset_state,
        test_state,
        increment,
        reload_term,
        generate_state,
        divide_state,
        mult_add_state,
        done_state
    );
    signal state, next_state : state_type;

    -- Status signals from datapath to control unit
    signal term_is_one : std_logic;
    signal term_is_even : std_logic;
    signal length_is_9 : std_logic;

    -- Control signals from control unit to datapath
    signal reset_number : std_logic;
    signal inc_number : std_logic;
    signal reset_term : std_logic;
    signal load_term : std_logic;
    signal shift_term : std_logic;
    signal mult_add_term : std_logic;
    signal reset_length : std_logic;
    signal inc_length : std_logic;
    signal reset_done : std_logic;
    signal load_done : std_logic;

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
    -- Slow clock from the 100 MHz board clock to 1Hz
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

    -- Display refresh counter
    display_counter: process(clk_in, reset)
    begin
        if reset = '1' then
            q_reg <= (others => '0');
        elsif (clk_in'event and clk_in = '1') then
            q_reg <= q_next;
        end if;
    end process;
    q_next <= q_reg + 1;

    -- Status signals
    term_is_one <= '1' when term_out = "0000001" else '0';
    term_is_even <= '1' when term_out(0) = '0' else '0';
    length_is_9 <= '1' when length >= "1001" else '0';

    -- ASM state register
    state_register: process(clk, reset)
    begin
        if reset = '1' then
            state <= reset_state;
        elsif (clk'event and clk = '1') then
            state <= next_state;
        end if;
    end process;

    -- Control unit
    control_unit: process(state, term_is_one, term_is_even, length_is_9)
    begin
        next_state <= state;
        reset_number <= '0';
        inc_number <= '0';
        reset_term <= '0';
        load_term <= '0';
        shift_term <= '0';
        mult_add_term <= '0';
        reset_length <= '0';
        inc_length <= '0';
        reset_done <= '0';
        load_done <= '0';
        case state is
            when reset_state =>
                reset_number <= '1';
                reset_term <= '1';
                reset_length <= '1';
                reset_done <= '1';
                next_state <= test_state;
            when test_state =>
                if length_is_9 = '1' then
                    next_state <= done_state;
                elsif term_is_one = '1' then
                    next_state <= increment;
                else
                    next_state <= generate_state;
                end if;
            when increment =>
                inc_number <= '1';
                next_state <= reload_term;
            when reload_term =>
                load_term <= '1';
                reset_length <= '1';
                next_state <= test_state;
            when generate_state =>
                inc_length <= '1';
                if term_is_even = '1' then
                    next_state <= divide_state;
                else
                    next_state <= mult_add_state;
                end if;
            when divide_state =>
                shift_term <= '1';
                next_state <= test_state;
            when mult_add_state =>
                mult_add_term <= '1';
                next_state <= test_state;
            when done_state =>
                load_done <= '1';
                next_state <= done_state;
        end case;
    end process;

    -- Number register
    number_register: process(clk, reset)
    begin
        if reset = '1' then
            number_out <= "0000001";
        elsif (clk'event and clk = '1') then
            if reset_number = '1' then
                number_out <= "0000001";
            elsif inc_number = '1' then
                number_out <= number_out + 1;
            end if;
        end if;
    end process;

    -- Term register
    term_register: process(clk, reset)
    begin
        if reset = '1' then
            term_out <= "0000001";
        elsif (clk'event and clk = '1') then
            if reset_term = '1' then
                term_out <= "0000001";
            elsif load_term = '1' then
                term_out <= number_out;
            elsif shift_term = '1' then
                term_out <= '0' & term_out(6 downto 1);
            elsif mult_add_term = '1' then
                term_out <= resize(term_out * 3 + 1, 7);
            end if;
        end if;
    end process;

    -- Length register
    length_register: process(clk, reset)
    begin
        if reset = '1' then
            length <= "0001";
        elsif (clk'event and clk = '1') then
            if reset_length = '1' then
                length <= "0001";
            elsif inc_length = '1' then
                length <= length + 1;
            end if;
        end if;
    end process;

    -- Done register
    done_register: process(clk, reset)
    begin
        if reset = '1' then
            done <= '0';
        elsif (clk'event and clk = '1') then
            if reset_done = '1' then
                done <= '0';
            elsif load_done = '1' then
                done <= '1';
            end if;
        end if;
    end process;
    done_out <= done;

    -- Binary to BCD converter for term_out
    bcd_converter: process(term_out)
        variable temp : unsigned(6 downto 0);
        variable tens : unsigned(3 downto 0);
    begin
        temp := term_out;
        tens := "0000";
        for i in 0 to 9 loop
            if temp >= 10 then
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

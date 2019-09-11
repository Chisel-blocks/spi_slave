library ieee;
use ieee.std_logic_arith.all;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all; 
 
entity tb_spi_slave is
end entity;

architecture behav of tb_spi_slave is
constant ClkPeriod: time := 1 ns;  
constant SClkPeriod: time := 11 ns;  
CONSTANT size_config:integer:=8;
CONSTANT size_monitor:integer:=8;
CONSTANT size: INTEGER:=size_monitor+size_config;
SIGNAL mosi:std_logic;
SIGNAL miso: std_logic;
SIGNAL cs  :std_logic;
SIGNAL sclk:std_logic:='0';
SIGNAL sclk_h:std_logic:='0';
SIGNAL config_value :std_logic_vector(size_config-1 downto 0);
SIGNAL monitor_dummy :std_logic_vector(size_monitor-1 downto 0);
SIGNAL config_register :std_logic_vector(size_config-1 downto 0);
SIGNAL monitor_register:std_logic_vector(size_monitor-1 downto 0);
--SIGNAL mode_select:std_logic:='0';
SIGNAL mclk:std_logic:='1';
SIGNAL rst:std_logic;
SIGNAL DONE :BOOLEAN:=FALSE;
--signal observation_register_before_shifting : std_logic_vector((size_config+size_monitor-1) downto 0);
--signal observation_register_after_shifting : std_logic_vector((size_config+size_monitor-1) downto 0);

BEGIN
monitor_dummy<=(OTHERS=>'0');

psclk:PROCESS
BEGIN
    WHILE (NOT DONE) LOOP
        sclk_h<=NOT sclk_h;
        WAIT FOR SClkPeriod/2.0;
    END LOOP;
    WAIT;
END PROCESS;

pmclk:PROCESS
BEGIN
    WHILE (NOT DONE) LOOP
        mclk<=NOT mclk;
        WAIT FOR ClkPeriod/2.0;
    END LOOP;
    WAIT;
END PROCESS;

spi_simulation:process
BEGIN
    rst <= '1';
    cs<='1';
    config_value<="01010101";
    monitor_register<="11100011";
    WAIT FOR SClkPeriod;

    rst <= '0';
    WAIT FOR SClkPeriod;

    cs<='0';
    WAIT FOR size*SClkPeriod;

    cs<= '1';
    monitor_register<="01010101";
    config_value<="10000001";
    monitor_register<="11100011";
    WAIT FOR SClkPeriod;

    cs<= '0';
    --mode_select<='1';
    wait for size*SClkPeriod;

    cs<='1';
    config_value<="10011001";
    monitor_register<="11110000";
    WAIT FOR SClkPeriod;

    cs<= '0';
    WAIT FOR size*SClkPeriod;

    cs<='1';
    WAIT FOR size*SClkPeriod;

    DONE<=TRUE;
    WAIT;
END PROCESS;

 
sclk<=TRANSPORT sclk_h AND (NOT cs) AFTER 1 ns;

mosigen:PROCESS(sclk,DONE,cs)
   VARIABLE v_master_data: STD_LOGIC_VECTOR(size-1 DOWNTO 0);
   VARIABLE v_count: INTEGER:=0;
BEGIN

IF (NOT DONE) THEN
    IF cs='1' THEN
       v_count:=0;
    END IF;

    IF(rising_edge(sclk)) THEN
        v_master_data:=config_value & monitor_dummy;
        mosi<=v_master_data(v_count);
        v_count:=v_count+1;
    END IF;
END IF;
END PROCESS;

		
DUT : ENTITY work.spi_slave
	--GENERIC MAP(
	--	size_config  =>8,
	--	size_monitor =>8
	--	)
	PORT MAP(
		io_mosi             => mosi, 		
		io_miso             => miso,		
		io_cs               => cs,		
		io_sclk             => sclk,		
		io_config_out       => config_register,
		io_monitor_in       => monitor_register,
		clock               => mclk,
        reset               => rst
		);
END ARCHITECTURE;


test:
	nvim --noplugins --headless -u ./tests/minimal_init.vim -c "PlenaryBustedDirectory lua/ {minimal_init = './tests/minimal_init.vim', sequential = true}" -c "qa"
	nvim --noplugins --headless -u ./tests/minimal_init.vim -c "PlenaryBustedDirectory tests/ {minimal_init = './tests/minimal_init.vim', sequential = true}" -c "qa"

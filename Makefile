APP      := pluf
PLC      ?= $(HOME)/mipt/04/CC/plum/bin/plc
MODULAR  ?= ../../PLUM/modular
PLCFLAGS ?= -O2 -g
LDLIBS   ?= -lm -lX11 -lXft -lXrender -lpthread
STD       = $(shell $(PLC) --print-std)
LIBMOD    = $(MODULAR)/build/libmodular.a
SRC       = $(wildcard src/*.pl)
OBJ       = $(SRC:src/%.pl=obj/%.o)
# what the tests link: everything but main, which they have their own of
LIB_OBJ   = $(filter-out obj/main.o,$(OBJ))
# every test/*_test.pl is a program of its own
TESTS     = $(patsubst test/%.pl,%,$(wildcard test/*_test.pl))

# a recipe that pipes fails when what it piped from did
SHELL      := /bin/bash
.SHELLFLAGS := -o pipefail -c

ifeq ($(V),1)
  Q :=
else
  Q := @
endif

# --- the log's colours: gruvbox dark, 24-bit -----------------------------------

# make's own output is captured by $(shell); its stderr is still the terminal
COLOR ?= $(if $(NO_COLOR),0,$(shell [ -t 2 ] && echo 1 || echo 0))
ifeq ($(COLOR),1)
  ESC    := $(shell printf '\033')
  rgb     = $(ESC)[38;2;$(1);$(2);$(3)m
  RST    := $(ESC)[0m
  BOLD   := $(ESC)[1m
  FG     := $(call rgb,235,219,178)
  GRAY   := $(call rgb,146,131,116)
  GREEN  := $(call rgb,184,187,38)
  YELLOW := $(call rgb,250,189,47)
  BLUE   := $(call rgb,131,165,152)
  AQUA   := $(call rgb,142,192,124)
  ORANGE := $(call rgb,254,128,25)
endif

# a step of the log: its tag in a colour, then a path, its folder dimmed --
#   PLC   src/app.pl
step = @printf '  %s%-5s%s %s%s%s%s%s\n' '$(BOLD)$(1)' '$(2)' '$(RST)' '$(GRAY)' '$(patsubst ./,,$(dir $(3)))' '$(FG)' '$(notdir $(3))' '$(RST)'

# modular's own log, through its Makefile, in the same colours: its tags
# aqua, its paths under modular/; anything else -- an error -- as it is
LIBLOG = awk '$$1 ~ /^[A-Z]+$$/ && NF == 2 { n = split($$2, p, "/"); d = substr($$2, 1, length($$2) - length(p[n])); printf "  %s%-5s%s %smodular/%s%s%s%s\n", "$(BOLD)$(AQUA)", $$1, "$(RST)", "$(GRAY)", d, "$(FG)", p[n], "$(RST)"; fflush(); next } { print; fflush() }'

# --- building ---------------------------------------------------------------------

$(APP): $(OBJ) $(LIBMOD)
	$(call step,$(GREEN),LD,$@)
	$(Q)cc $(OBJ) $(LIBMOD) $(STD) -o $@ $(LDLIBS)
	@printf '  %s✓%s %s%s%s  %s%s, %s files of PLUM%s\n' '$(BOLD)$(GREEN)' '$(RST)' '$(BOLD)$(FG)' '$@' '$(RST)' '$(GRAY)' "$$(du -h $@ | cut -f1)" '$(words $(SRC))' '$(RST)'

# the library's own Makefile knows when it is out of date: asked every
# time, quietly; the program is linked again only when the archive changed
$(LIBMOD): FORCE
	$(Q)$(MAKE) -s --no-print-directory -C $(MODULAR) lib | $(LIBLOG)

obj/%.o: src/%.pl
	@mkdir -p $(@D)
	$(call step,$(YELLOW),PLC,$<)
	$(Q)$(PLC) -c -MD $(PLCFLAGS) -I $(MODULAR)/lib $< -o $@

obj/test/%.o: test/%.pl
	@mkdir -p $(@D)
	$(call step,$(YELLOW),PLC,$<)
	$(Q)$(PLC) -c -MD $(PLCFLAGS) -I $(MODULAR)/lib $< -o $@

obj/test/%: obj/test/%.o $(LIB_OBJ) $(LIBMOD)
	$(call step,$(GREEN),LD,$@)
	$(Q)cc $< $(LIB_OBJ) $(LIBMOD) $(STD) -o $@ $(LDLIBS)

-include $(OBJ:.o=.d) $(TESTS:%=obj/test/%.d)

run: $(APP)
	@./$(APP) $(ARGS)

gui: $(APP)
	@./$(APP) --gui $(ARGS)

test: $(APP) $(TESTS:%=obj/test/%)
	@for t in $(TESTS); do printf '  %s%-5s%s %s\n' '$(BOLD)$(BLUE)' TEST '$(RST)' "$$t"; obj/test/$$t || exit 1; done

# into PREFIX/bin
PREFIX ?= $(HOME)/.local
install: $(APP)
	$(call step,$(GREEN),INST,$(PREFIX)/bin/$(APP))
	$(Q)install -Dm755 $(APP) $(PREFIX)/bin/$(APP)

uninstall:
	$(Q)rm -f $(PREFIX)/bin/$(APP)

clean:
	$(call step,$(ORANGE),CLEAN,$(APP))
	$(Q)rm -rf obj $(APP)

.PHONY: run gui test install uninstall clean FORCE
.PRECIOUS: obj/test/%.o
FORCE:

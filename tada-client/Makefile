# C64 Game Client Makefile

# Configuration
ASM = wine ~/bin/c64list4_04.exe
ASMFLAGS = -prg -sym -symlvl:general -verbose -ovr
PYTHON = python3

# File names
SOURCE = screen_scroll.asm
STEM = $(basename $(SOURCE))
OUTPUT = $(STEM).prg
LABELS_SYM = $(STEM).sym
LABELS_VICE = $(STEM).vice

# Phony targets (not actual files)
.PHONY: all clean vice run help

# Default target
all: $(OUTPUT)

# Assemble the program (generates both .prg and .sym)
$(OUTPUT): $(SOURCE)
	$(ASM) $(SOURCE) $(ASMFLAGS)

# Build and prepare for VICE
vice: $(OUTPUT) $(LABELS_VICE)
	@echo "Build complete! Ready for VICE"
	@echo "Run with: x64sc -moncommands $(LABELS_VICE) $(OUTPUT)"

# Convert c64list .sym format to VICE format
$(LABELS_VICE): $(LABELS_SYM)
	@echo "Converting labels to VICE format..."
	# clear existing labels:
	@echo "cl" > $(LABELS_VICE)
	@awk '/=/ { \
		# Normalize whitespace: \
		gsub(/[ \t]+/, " "); \
		# Strip carriage returns from Windows line endings: \
		gsub(/\r/, "") ; \
		# Split the line into fields: \
		split($$$$0, a, " "); \
		# assign names to fields: \
		name = a[1]; \
		addr = a[3]; \
		# Result: al $ff .zp_ff \
		printf "al %s .%s\n", addr, name \
	}' $(LABELS_SYM) >> $(LABELS_VICE)
	@echo "Labels converted: $(LABELS_VICE)"

# Alternative: Use your existing Python script
vice-python: $(OUTPUT)
	$(PYTHON) ~/bin/make-vice-labels.py $(LABELS_SYM) $(STEM)

# Run in VICE with labels
run: vice
	x64sc -moncommands $(LABELS_VICE) -basicload $(OUTPUT)

# Clean build artifacts
clean:
	rm -f $(OUTPUT) $(LABELS_SYM) $(LABELS_VICE)

# Help target
help:
	@echo "Available targets:"
	@echo "  make             - Assemble the program"
	@echo "  make vice        - Assemble and convert labels for VICE (AWK)"
	@echo "  make vice-python - Assemble and convert labels (Python script)"
	@echo "  make run         - Assemble, convert labels, and run in VICE"
	@echo "  make clean       - Remove all build artifacts"
	@echo "  make help        - Show this help message"

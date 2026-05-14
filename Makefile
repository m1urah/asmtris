TARGET = asmtris

BUILD_DIR := build
SRC_DIRS := src

SRCS = $(shell find $(SRC_DIRS) -name '*.s')
OBJS = $(patsubst $(SRC_DIRS)/%.s,$(BUILD_DIR)/%.o,$(SRCS))

$(BUILD_DIR)/%.o: $(SRC_DIRS)/%.s
	mkdir -p $(dir $@)
	nasm -f elf64 -o $@ $<

$(TARGET): $(OBJS)
	@echo "Linking object files to create $(TARGET)"
	ld -o $(TARGET) $(OBJS)

.PHONY: clean
clean:
	rm -rf $(BUILD_DIR)
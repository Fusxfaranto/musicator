
NAME := main
C_SRCS := $(wildcard *.c)
C_HEADERS := $(wildcard *.h)
D_SRCS := $(wildcard *.d)
C_OBJS := $(patsubst %.c,out/%.o,$(C_SRCS))
D_OBJS := $(patsubst %.d,out/%.o,$(D_SRCS))
OBJS := $(C_OBJS) $(D_OBJS)
#INCLUDE_DIRS :=
#LIBRARY_DIRS :=
#LIBRARIES :=

#CPPFLAGS += $(foreach includedir,$(INCLUDE_DIRS),-I$(includedir))
#LDFLAGS += $(foreach librarydir,$(LIBRARY_DIRS),-L$(librarydir))
#LDFLAGS += $(foreach library,$(LIBRARIES),-l$(library))

#DC := gdc
DC := ldc2
#DC := dmd

CFLAGS := -m64 -fPIC -g -c -O0 -std=c11 -pedantic -Wall -Werror -Wno-error=unused-variable -Wmissing-field-initializers -Wconversion -Iinclude #-I/usr/include/freetype2/ #-Iftgl/src/
CFLAGS += -Icubeb/include/ -Icubeb/build/exports/
#CLDFLAGS += -Lcubeb/build/ -llibcubeb
CSTATIC_LIBS := cubeb/build/libcubeb.a

DFLAGS := -m64 -g -c -O
#DFLAGS += -d-debug=prof
DFLAGS += # -debug=prof # -profile=gc
#LDFLAGS := -Llib -lm -lSOIL -lGLEW -lglfw -lGL

DFLAGS += -unittest

LDFLAGS :=

LDFLAGS += -L=-l:libmusicator.a
LDFLAGS += -L=-Llib -L=-Lout
LDFLAGS += -L=-lm
LDFLAGS += -L=-lstdc++
LDFLAGS += -L=-lasound -L=-lpthread

RTMIDI_OBJS := out/rtmidi/rtmidi.o out/rtmidi/rtmidi_c.o

.PHONY: all clean distclean

all: $(NAME)

$(NAME): $(D_OBJS) out/libmusicator.a $(RTMIDI_OBJS)
#	$(DC) $(OBJS) $(LDFLAGS) -o $(NAME)
	$(DC) $(OBJS) $(RTMIDI_OBJS) $(LDFLAGS) -of$(NAME)

$(D_OBJS): $(D_SRCS) $(C_HEADERS)
#	dstep $(C_HEADERS) $(CFLAGS) -o ./bindings/
	dstep $(C_HEADERS) $(CFLAGS) -o c_bindings.d
	$(DC) $(D_SRCS) $(DFLAGS) -od=out

$(RTMIDI_OBJS): rtmidi/*.cpp rtmidi/*.h
	mkdir -p out/rtmidi
	dstep rtmidi/rtmidi_c.h -o rtmidi_c.d
	g++ -c -O0 -g -Wall -D__LINUX_ALSA__ -o out/rtmidi/rtmidi.o -I rtmidi rtmidi/RtMidi.cpp
	g++ -c -O0 -g -Wall -D__LINUX_ALSA__ -o out/rtmidi/rtmidi_c.o -I rtmidi rtmidi/rtmidi_c.cpp

out/libmusicator.a: $(C_OBJS)
#	ar rcs out/libmusicator.a $(C_OBJS) $(CSTATIC_LIBS)
#	libtool --mode=link cc -static -o out/libmusicator.a $(C_OBJS) $(CSTATIC_LIBS)
	echo "CREATE $@" > out/ar_script.mri
	for a in $(CSTATIC_LIBS); do (echo "ADDLIB $$a" >> out/ar_script.mri); done
	echo "ADDMOD $(C_OBJS)" >> out/ar_script.mri
	echo "SAVE" >> out/ar_script.mri
	echo "END" >> out/ar_script.mri
	$(AR) -M < out/ar_script.mri

$(C_OBJS): $(C_SRCS) $(C_HEADERS)
	$(CC) $(C_SRCS) $(CFLAGS) -o $@

clean:
	@- $(RM) $(NAME)
	@- $(RM) $(OBJS)
	@- $(RM) -rf out/*

distclean: clean

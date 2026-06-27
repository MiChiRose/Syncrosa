import sys
import struct

def patch_macho(filepath):
    print(f"Opening binary: {filepath}")
    with open(filepath, 'rb') as f:
        data = bytearray(f.read())
        
    magic = struct.unpack('<I', data[0:4])[0]
    if magic == 0xFEEDFACF:
        endian = '<'
    elif magic == 0xCFFAEDFE:
        endian = '>'
    else:
        print("Not a valid 64-bit Mach-O binary or wrong magic number.")
        return False
        
    cputype, cpusubtype, filetype, ncmds, sizeofcmds, flags, reserved = struct.unpack(
        endian + 'IIIIIII', data[4:32]
    )
    
    offset = 32
    patched = False
    
    for i in range(ncmds):
        if offset + 8 > len(data):
            break
        cmd, cmdsize = struct.unpack(endian + 'II', data[offset:offset+8])
        
        if cmd == 0x24: # LC_VERSION_MIN_MACOSX
            version_offset = offset + 8
            new_version = (10 << 16) | (9 << 8) | 0 # 10.9.0
            struct.pack_into(endian + 'I', data, version_offset, new_version)
            patched = True
            print("LC_VERSION_MIN_MACOSX found and patched to 10.9.0")
            
        offset += cmdsize
        
    if patched:
        with open(filepath, 'wb') as f:
            f.write(data)
        print("Binary successfully patched!")
        return True
    else:
        print("LC_VERSION_MIN_MACOSX not found.")
        return False

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python patch_binary.py <path_to_binary>")
    else:
        patch_macho(sys.argv[1])

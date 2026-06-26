#include "CDDC.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <unistd.h>

// --- Private IOAVService API (declared as in m1ddc / MonitorControl) ---------
// These symbols live in IOKit.framework but are not in the public headers.
typedef CFTypeRef IOAVServiceRef;
extern IOAVServiceRef IOAVServiceCreateWithService(CFAllocatorRef allocator, io_service_t service);
extern IOReturn IOAVServiceWriteI2C(IOAVServiceRef service, uint32_t chipAddress,
                                    uint32_t dataAddress, void *inputBuffer, uint32_t inputBufferSize);
extern IOReturn IOAVServiceReadI2C(IOAVServiceRef service, uint32_t chipAddress,
                                   uint32_t offset, void *outputBuffer, uint32_t outputBufferSize);

#define DDC_VCP_LUMINANCE 0x10

// Collects external (non-embedded) AV services. Caller must CFRelease each.
static CFIndex collect_services(IOAVServiceRef *out, CFIndex maxCount) {
    io_iterator_t iterator = IO_OBJECT_NULL;
    CFMutableDictionaryRef matching = IOServiceMatching("DCPAVServiceProxy");
    if (IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) != KERN_SUCCESS) {
        return 0;
    }
    CFIndex count = 0;
    io_service_t entry;
    while ((entry = IOIteratorNext(iterator)) != IO_OBJECT_NULL && count < maxCount) {
        CFStringRef location = IORegistryEntryCreateCFProperty(entry, CFSTR("Location"),
                                                               kCFAllocatorDefault, 0);
        int embedded = 0;
        if (location) {
            embedded = CFStringCompare(location, CFSTR("Embedded"), 0) == kCFCompareEqualTo;
            CFRelease(location);
        }
        if (!embedded) {
            IOAVServiceRef service = IOAVServiceCreateWithService(kCFAllocatorDefault, entry);
            if (service) {
                out[count++] = service;
            }
        }
        IOObjectRelease(entry);
    }
    IOObjectRelease(iterator);
    return count;
}

static void release_services(IOAVServiceRef *services, CFIndex count) {
    for (CFIndex i = 0; i < count; i++) {
        if (services[i]) CFRelease(services[i]);
    }
}

static int write_vcp(IOAVServiceRef service, uint8_t vcp, uint8_t value) {
    uint8_t data[6];
    data[0] = 0x84;                         // 0x80 | length(4)
    data[1] = 0x03;                         // set VCP feature
    data[2] = vcp;
    data[3] = (uint8_t)(value >> 8);
    data[4] = (uint8_t)(value & 0xFF);
    data[5] = 0x6E ^ 0x51 ^ data[0] ^ data[1] ^ data[2] ^ data[3] ^ data[4];
    IOReturn err = IOAVServiceWriteI2C(service, 0x37, 0x51, data, 6);
    usleep(10000);
    return err == KERN_SUCCESS;
}

static int read_vcp(IOAVServiceRef service, uint8_t vcp) {
    uint8_t request[4];
    request[0] = 0x82;                       // 0x80 | length(2)
    request[1] = 0x01;                       // get VCP feature
    request[2] = vcp;
    request[3] = 0x6E ^ 0x51 ^ request[0] ^ request[1] ^ request[2];
    if (IOAVServiceWriteI2C(service, 0x37, 0x51, request, 4) != KERN_SUCCESS) {
        return -1;
    }
    usleep(40000);

    uint8_t reply[11] = {0};
    if (IOAVServiceReadI2C(service, 0x37, 0x51, reply, 11) != KERN_SUCCESS) {
        return -1;
    }
    if (reply[2] != 0x02 || reply[4] != vcp) {
        return -1;
    }
    return reply[9];
}

int cddc_external_display_count(void) {
    IOAVServiceRef services[16];
    CFIndex count = collect_services(services, 16);
    release_services(services, count);
    return (int)count;
}

int cddc_set_brightness(int index, int percent) {
    if (index < 0) return 0;
    if (percent < 0) percent = 0;
    if (percent > 100) percent = 100;
    IOAVServiceRef services[16];
    CFIndex count = collect_services(services, 16);
    int ok = 0;
    if (index < count) {
        ok = write_vcp(services[index], DDC_VCP_LUMINANCE, (uint8_t)percent);
    }
    release_services(services, count);
    return ok;
}

int cddc_get_brightness(int index) {
    if (index < 0) return -1;
    IOAVServiceRef services[16];
    CFIndex count = collect_services(services, 16);
    int value = -1;
    if (index < count) {
        value = read_vcp(services[index], DDC_VCP_LUMINANCE);
    }
    release_services(services, count);
    return value;
}

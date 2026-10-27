// Declarations for the IOHIDEventSystemClient API, which IOKit exports but does not publish headers for.
// Apple Silicon reports some temperatures (SSD, battery gauge, PMU) only through it.

#ifndef CIOHID_H
#define CIOHID_H

#include <CoreFoundation/CoreFoundation.h>

typedef struct CF_BRIDGED_TYPE(id) __IOHIDEventSystemClient *IOHIDEventSystemClientRef;
typedef struct CF_BRIDGED_TYPE(id) __IOHIDServiceClient *IOHIDServiceClientRef;
typedef struct CF_BRIDGED_TYPE(id) __IOHIDEvent *IOHIDEventRef;

CF_RETURNS_RETAINED IOHIDEventSystemClientRef _Nullable IOHIDEventSystemClientCreate(CFAllocatorRef _Nullable allocator);
int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef _Nonnull client, CFDictionaryRef _Nonnull matching);
CF_RETURNS_RETAINED CFArrayRef _Nullable IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef _Nonnull client);
CF_RETURNS_RETAINED CFTypeRef _Nullable IOHIDServiceClientCopyProperty(IOHIDServiceClientRef _Nonnull service, CFStringRef _Nonnull key);
CF_RETURNS_RETAINED IOHIDEventRef _Nullable IOHIDServiceClientCopyEvent(IOHIDServiceClientRef _Nonnull service, int64_t type, int32_t options, int64_t timestamp);
double IOHIDEventGetFloatValue(IOHIDEventRef _Nonnull event, int32_t field);

#endif

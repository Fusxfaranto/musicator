/************************************************************************/
/*! \defgroup C-interface
    @{

    \brief C interface to realtime MIDI input/output C++ classes.

    RtMidi offers a C-style interface, principally for use in binding
    RtMidi to other programming languages.  All structs, enums, and
    functions listed here have direct analogs (and simply call to)
    items in the C++ RtMidi class and its supporting classes and
    types
*/
/************************************************************************/

/*!
  \file rtmidi_c.h
 */

extern (C): //__declspec(dllimport)

//! \brief Wraps an RtMidi object for C function return statuses.
struct RtMidiWrapper
{
    //! The wrapped RtMidi object.
    void* ptr;
    void* data;

    //! True when the last function call was OK.
    bool ok;

    //! If an error occured (ok != true), set to an error message.
    const(char)* msg;
}

//! \brief Typedef for a generic RtMidi pointer.
alias RtMidiPtr = RtMidiWrapper*;

//! \brief Typedef for a generic RtMidiIn pointer.
alias RtMidiInPtr = RtMidiWrapper*;

//! \brief Typedef for a generic RtMidiOut pointer.
alias RtMidiOutPtr = RtMidiWrapper*;

//! \brief MIDI API specifier arguments.  See \ref RtMidi::Api.
enum RtMidiApi
{
    RTMIDI_API_UNSPECIFIED = 0, /*!< Search for a working compiled API. */
    RTMIDI_API_MACOSX_CORE = 1, /*!< Macintosh OS-X CoreMIDI API. */
    RTMIDI_API_LINUX_ALSA = 2, /*!< The Advanced Linux Sound Architecture API. */
    RTMIDI_API_UNIX_JACK = 3, /*!< The Jack Low-Latency MIDI Server API. */
    RTMIDI_API_WINDOWS_MM = 4, /*!< The Microsoft Multimedia MIDI API. */
    RTMIDI_API_RTMIDI_DUMMY = 5, /*!< A compilable but non-functional API. */
    RTMIDI_API_NUM = 6 /*!< Number of values in this enum. */
}

//! \brief Defined RtMidiError types. See \ref RtMidiError::Type.
enum RtMidiErrorType
{
    RTMIDI_ERROR_WARNING = 0, /*!< A non-critical error. */
    RTMIDI_ERROR_DEBUG_WARNING = 1, /*!< A non-critical error which might be useful for debugging. */
    RTMIDI_ERROR_UNSPECIFIED = 2, /*!< The default, unspecified error type. */
    RTMIDI_ERROR_NO_DEVICES_FOUND = 3, /*!< No devices found on system. */
    RTMIDI_ERROR_INVALID_DEVICE = 4, /*!< An invalid device ID was specified. */
    RTMIDI_ERROR_MEMORY_ERROR = 5, /*!< An error occured during memory allocation. */
    RTMIDI_ERROR_INVALID_PARAMETER = 6, /*!< An invalid parameter was specified to a function. */
    RTMIDI_ERROR_INVALID_USE = 7, /*!< The function was called incorrectly. */
    RTMIDI_ERROR_DRIVER_ERROR = 8, /*!< A system driver error occured. */
    RTMIDI_ERROR_SYSTEM_ERROR = 9, /*!< A system error occured. */
    RTMIDI_ERROR_THREAD_ERROR = 10 /*!< A thread error occured. */
}

/*! \brief The type of a RtMidi callback function.
 *
 * \param timeStamp   The time at which the message has been received.
 * \param message     The midi message.
 * \param userData    Additional user data for the callback.
 *
 * See \ref RtMidiIn::RtMidiCallback.
 */
alias RtMidiCCallback = void function (
    double timeStamp,
    const(ubyte)* message,
    size_t messageSize,
    void* userData);

/* RtMidi API */

/*! \brief Determine the available compiled MIDI APIs.
 *
 * If the given `apis` parameter is null, returns the number of available APIs.
 * Otherwise, fill the given apis array with the RtMidi::Api values.
 *
 * \param apis  An array or a null value.
 * \param apis_size  Number of elements pointed to by apis
 * \return number of items needed for apis array if apis==NULL, or
 *         number of items written to apis array otherwise.  A negative
 *         return value indicates an error.
 *
 * See \ref RtMidi::getCompiledApi().
*/
int rtmidi_get_compiled_api (RtMidiApi* apis, uint apis_size);

//! \brief Return the name of a specified compiled MIDI API.
//! See \ref RtMidi::getApiName().
const(char)* rtmidi_api_name (RtMidiApi api);

//! \brief Return the display name of a specified compiled MIDI API.
//! See \ref RtMidi::getApiDisplayName().
const(char)* rtmidi_api_display_name (RtMidiApi api);

//! \brief Return the compiled MIDI API having the given name.
//! See \ref RtMidi::getCompiledApiByName().
RtMidiApi rtmidi_compiled_api_by_name (const(char)* name);

//! \internal Report an error.
void rtmidi_error (RtMidiErrorType type, const(char)* errorString);

/*! \brief Open a MIDI port.
 *
 * \param port      Must be greater than 0
 * \param portName  Name for the application port.
 *
 * See RtMidi::openPort().
 */
void rtmidi_open_port (RtMidiPtr device, uint portNumber, const(char)* portName);

/*! \brief Creates a virtual MIDI port to which other software applications can
 * connect.
 *
 * \param portName  Name for the application port.
 *
 * See RtMidi::openVirtualPort().
 */
void rtmidi_open_virtual_port (RtMidiPtr device, const(char)* portName);

/*! \brief Close a MIDI connection.
 * See RtMidi::closePort().
 */
void rtmidi_close_port (RtMidiPtr device);

/*! \brief Return the number of available MIDI ports.
 * See RtMidi::getPortCount().
 */
uint rtmidi_get_port_count (RtMidiPtr device);

/*! \brief Return a string identifier for the specified MIDI input port number.
 * See RtMidi::getPortName().
 */
const(char)* rtmidi_get_port_name (RtMidiPtr device, uint portNumber);

/* RtMidiIn API */

//! \brief Create a default RtMidiInPtr value, with no initialization.
RtMidiInPtr rtmidi_in_create_default ();

/*! \brief Create a  RtMidiInPtr value, with given api, clientName and queueSizeLimit.
 *
 *  \param api            An optional API id can be specified.
 *  \param clientName     An optional client name can be specified. This
 *                        will be used to group the ports that are created
 *                        by the application.
 *  \param queueSizeLimit An optional size of the MIDI input queue can be
 *                        specified.
 *
 * See RtMidiIn::RtMidiIn().
 */
RtMidiInPtr rtmidi_in_create (RtMidiApi api, const(char)* clientName, uint queueSizeLimit);

//! \brief Free the given RtMidiInPtr.
void rtmidi_in_free (RtMidiInPtr device);

//! \brief Returns the MIDI API specifier for the given instance of RtMidiIn.
//! See \ref RtMidiIn::getCurrentApi().
RtMidiApi rtmidi_in_get_current_api (RtMidiPtr device);

//! \brief Set a callback function to be invoked for incoming MIDI messages.
//! See \ref RtMidiIn::setCallback().
void rtmidi_in_set_callback (RtMidiInPtr device, RtMidiCCallback callback, void* userData);

//! \brief Cancel use of the current callback function (if one exists).
//! See \ref RtMidiIn::cancelCallback().
void rtmidi_in_cancel_callback (RtMidiInPtr device);

//! \brief Specify whether certain MIDI message types should be queued or ignored during input.
//! See \ref RtMidiIn::ignoreTypes().
void rtmidi_in_ignore_types (RtMidiInPtr device, bool midiSysex, bool midiTime, bool midiSense);

/*! Fill the user-provided array with the data bytes for the next available
 * MIDI message in the input queue and return the event delta-time in seconds.
 *
 * \param message   Must point to a char* that is already allocated.
 *                  SYSEX messages maximum size being 1024, a statically
 *                  allocated array could
 *                  be sufficient.
 * \param size      Is used to return the size of the message obtained.
 *
 * See RtMidiIn::getMessage().
 */
double rtmidi_in_get_message (RtMidiInPtr device, ubyte* message, size_t* size);

/* RtMidiOut API */

//! \brief Create a default RtMidiInPtr value, with no initialization.
RtMidiOutPtr rtmidi_out_create_default ();

/*! \brief Create a RtMidiOutPtr value, with given and clientName.
 *
 *  \param api            An optional API id can be specified.
 *  \param clientName     An optional client name can be specified. This
 *                        will be used to group the ports that are created
 *                        by the application.
 *
 * See RtMidiOut::RtMidiOut().
 */
RtMidiOutPtr rtmidi_out_create (RtMidiApi api, const(char)* clientName);

//! \brief Free the given RtMidiOutPtr.
void rtmidi_out_free (RtMidiOutPtr device);

//! \brief Returns the MIDI API specifier for the given instance of RtMidiOut.
//! See \ref RtMidiOut::getCurrentApi().
RtMidiApi rtmidi_out_get_current_api (RtMidiPtr device);

//! \brief Immediately send a single message out an open MIDI output port.
//! See \ref RtMidiOut::sendMessage().
int rtmidi_out_send_message (RtMidiOutPtr device, const(ubyte)* message, int length);

/*! }@ */

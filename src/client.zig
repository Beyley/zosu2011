const std = @import("std");
const network = @import("network");

const Self = @This();

pub const MAX_USERNAME_LENGTH = 32;

username_buf: [MAX_USERNAME_LENGTH]u8,
username: []u8,
password: [std.crypto.hash.Md5.digest_length]u8,
socket: network.Socket,
writer: std.io.BufferedWriter(4096, network.Socket.Writer),
write_mutex: std.Thread.Mutex,
last_heard_from: i64,

time_zone: i8,
display_city: bool,

//A set of temporary buffers we read into inside the `read` function
temp_read_buf: [4096]u8 = undefined,
temp_read_buf_slice: []u8 = undefined,
read_from_temp_buf: usize = 0,

///Resets the read buffer, ignoring all data from the previous read
pub fn reset_read(self: *Self) !void {
    self.temp_read_buf_slice = self.temp_read_buf[0..self.socket.receive(&self.temp_read_buf)];
}

pub const Reader = std.io.Reader(*Self, network.Socket.Reader.Error, read);

pub fn reader(self: *Self) Reader {
    return Reader{
        .context = self,
    };
}

///Tries to read bytes from the client
pub fn read(self: *Self, buf: []u8) !usize {
    //A constantly updating buffer containing all the data we are going to be reading
    var rest_of_buf: []u8 = buf;

    while (rest_of_buf.len > 0) {
        //If we have any bytes at all in the temporary buffer left
        if (self.read_from_temp_buf < self.temp_read_buf_slice.len) {
            //Get the amount of bytes we are able to read in from the buffer
            const bytes_to_read = @min(self.temp_read_buf_slice.len - self.read_from_temp_buf, rest_of_buf.len);

            //Copy the bytes we *do* have into the output buffer
            @memcpy(
                rest_of_buf[0..bytes_to_read],
                self.temp_read_buf_slice[self.read_from_temp_buf .. self.read_from_temp_buf + bytes_to_read],
            );

            //Mark that we have read more from the buffer
            self.read_from_temp_buf += bytes_to_read;

            //If the amount of bytes left in the buffer equal the length of the data we have yet to read,
            if (bytes_to_read == rest_of_buf.len) {
                //We are done
                break;
            }

            //The rest of buf is the second chunk of the data we have not written to
            rest_of_buf = rest_of_buf[bytes_to_read..rest_of_buf.len];
        }

        //Read as much data as we can into the temp buffer
        self.temp_read_buf_slice = self.temp_read_buf[0..try self.socket.receive(&self.temp_read_buf)];

        //Reset the amount we have read from the temp buf
        self.read_from_temp_buf = 0;
    }

    return buf.len;
}

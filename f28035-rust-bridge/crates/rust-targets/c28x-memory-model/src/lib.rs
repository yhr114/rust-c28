#![no_std]

// Enabled by the future C28x target build (`--cfg c28x_target`).
#[cfg(c28x_target)]
pub mod target;

/// A byte address in Rust's logical, 8-bit-addressed memory space.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(transparent)]
pub struct LogicalByteAddress(pub u32);

/// The selected byte lane within one 16-bit C28x physical word.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ByteLane {
    Low,
    High,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct AddressParts {
    pub word_index: usize,
    pub lane: ByteLane,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct OutOfBounds;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct InvalidLength;

/// A bounds-checked view of logical 8-bit bytes packed into C28x words.
pub struct PackedBytes<'a> {
    words: &'a mut [u16],
    len: usize,
}

impl<'a> PackedBytes<'a> {
    pub fn new(words: &'a mut [u16], logical_len: usize) -> Result<Self, InvalidLength> {
        let capacity = words.len().checked_mul(2).ok_or(InvalidLength)?;
        if logical_len > capacity {
            return Err(InvalidLength);
        }
        Ok(Self {
            words,
            len: logical_len,
        })
    }

    pub const fn len(&self) -> usize {
        self.len
    }

    pub const fn is_empty(&self) -> bool {
        self.len == 0
    }

    pub fn get(&self, index: usize) -> Result<u8, OutOfBounds> {
        if index >= self.len {
            return Err(OutOfBounds);
        }
        read_byte(self.words, LogicalByteAddress(index as u32))
    }

    pub fn set(&mut self, index: usize, value: u8) -> Result<(), OutOfBounds> {
        if index >= self.len {
            return Err(OutOfBounds);
        }
        write_byte(self.words, LogicalByteAddress(index as u32), value)
    }

    pub fn read_u16_le(&self, index: usize) -> Result<u16, OutOfBounds> {
        let next = index.checked_add(1).ok_or(OutOfBounds)?;
        let low = self.get(index)?;
        let high = self.get(next)?;
        Ok(u16::from(low) | (u16::from(high) << 8))
    }

    pub fn write_u16_le(&mut self, index: usize, value: u16) -> Result<(), OutOfBounds> {
        let next = index.checked_add(1).ok_or(OutOfBounds)?;
        if next >= self.len {
            return Err(OutOfBounds);
        }
        self.set(index, value as u8)?;
        self.set(next, (value >> 8) as u8)
    }

    pub fn fill(&mut self, value: u8) {
        let packed = pack_bytes(value, value);
        let complete_words = self.len / 2;
        for word in &mut self.words[..complete_words] {
            *word = packed;
        }
        if self.len & 1 != 0 {
            let last = &mut self.words[complete_words];
            *last = (*last & 0xff00) | u16::from(value);
        }
    }

    pub fn physical_words(&self) -> &[u16] {
        self.words
    }
}

impl LogicalByteAddress {
    pub const fn split(self) -> AddressParts {
        AddressParts {
            word_index: (self.0 >> 1) as usize,
            lane: if self.0 & 1 == 0 {
                ByteLane::Low
            } else {
                ByteLane::High
            },
        }
    }
}

pub const fn pack_bytes(low: u8, high: u8) -> u16 {
    (low as u16) | ((high as u16) << 8)
}

pub const fn unpack_low(word: u16) -> u8 {
    (word & 0x00ff) as u8
}

pub const fn unpack_high(word: u16) -> u8 {
    ((word >> 8) & 0x00ff) as u8
}

pub fn read_byte(words: &[u16], address: LogicalByteAddress) -> Result<u8, OutOfBounds> {
    let parts = address.split();
    let word = *words.get(parts.word_index).ok_or(OutOfBounds)?;
    Ok(match parts.lane {
        ByteLane::Low => unpack_low(word),
        ByteLane::High => unpack_high(word),
    })
}

pub fn write_byte(
    words: &mut [u16],
    address: LogicalByteAddress,
    value: u8,
) -> Result<(), OutOfBounds> {
    let parts = address.split();
    let word = words.get_mut(parts.word_index).ok_or(OutOfBounds)?;
    *word = match parts.lane {
        ByteLane::Low => (*word & 0xff00) | value as u16,
        ByteLane::High => (*word & 0x00ff) | ((value as u16) << 8),
    };
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn splits_logical_addresses_into_word_and_lane() {
        assert_eq!(
            LogicalByteAddress(0).split(),
            AddressParts {
                word_index: 0,
                lane: ByteLane::Low
            }
        );
        assert_eq!(
            LogicalByteAddress(1).split(),
            AddressParts {
                word_index: 0,
                lane: ByteLane::High
            }
        );
        assert_eq!(
            LogicalByteAddress(2).split(),
            AddressParts {
                word_index: 1,
                lane: ByteLane::Low
            }
        );
    }

    #[test]
    fn layout_matches_two_little_endian_bytes_per_word() {
        assert_eq!(pack_bytes(0x11, 0x22), 0x2211);
        assert_eq!(pack_bytes(0x33, 0x44), 0x4433);
        assert_eq!(unpack_low(0x2211), 0x11);
        assert_eq!(unpack_high(0x2211), 0x22);
    }

    #[test]
    fn writes_preserve_the_adjacent_byte() {
        let mut words = [0x2211];
        write_byte(&mut words, LogicalByteAddress(0), 0xaa).unwrap();
        assert_eq!(words[0], 0x22aa);
        write_byte(&mut words, LogicalByteAddress(1), 0xbb).unwrap();
        assert_eq!(words[0], 0xbbaa);
    }

    #[test]
    fn reads_both_lanes_and_reports_bounds() {
        let words = [0x2211, 0x4433];
        assert_eq!(read_byte(&words, LogicalByteAddress(0)), Ok(0x11));
        assert_eq!(read_byte(&words, LogicalByteAddress(1)), Ok(0x22));
        assert_eq!(read_byte(&words, LogicalByteAddress(2)), Ok(0x33));
        assert_eq!(read_byte(&words, LogicalByteAddress(3)), Ok(0x44));
        assert_eq!(read_byte(&words, LogicalByteAddress(4)), Err(OutOfBounds));
    }

    #[test]
    fn safe_view_enforces_odd_logical_length() {
        let mut words = [0x2211, 0xaa33];
        let mut bytes = PackedBytes::new(&mut words, 3).unwrap();
        assert_eq!(bytes.len(), 3);
        assert_eq!(bytes.get(2), Ok(0x33));
        assert_eq!(bytes.get(3), Err(OutOfBounds));
        assert_eq!(bytes.set(3, 0x55), Err(OutOfBounds));
        assert_eq!(bytes.physical_words()[1], 0xaa33);
    }

    #[test]
    fn rejects_length_larger_than_physical_capacity() {
        let mut words = [0u16; 2];
        assert!(matches!(
            PackedBytes::new(&mut words, 5),
            Err(InvalidLength)
        ));
    }

    #[test]
    fn u16_access_works_at_even_and_cross_word_offsets() {
        let mut words = [0x2211, 0x4433, 0x6655];
        let mut bytes = PackedBytes::new(&mut words, 6).unwrap();
        assert_eq!(bytes.read_u16_le(0), Ok(0x2211));
        assert_eq!(bytes.read_u16_le(1), Ok(0x3322));
        bytes.write_u16_le(1, 0xbbaa).unwrap();
        assert_eq!(bytes.physical_words(), &[0xaa11, 0x44bb, 0x6655]);
        assert_eq!(bytes.read_u16_le(5), Err(OutOfBounds));
    }

    #[test]
    fn fill_handles_odd_length_without_touching_padding_lane() {
        let mut words = [0x2211, 0xaa33];
        let mut bytes = PackedBytes::new(&mut words, 3).unwrap();
        bytes.fill(0x5a);
        assert_eq!(bytes.physical_words(), &[0x5a5a, 0xaa5a]);
    }

    #[test]
    fn exhaustively_reads_every_physical_word_value() {
        for word in 0u16..=u16::MAX {
            assert_eq!(unpack_low(word), word as u8);
            assert_eq!(unpack_high(word), (word >> 8) as u8);
        }
    }

    #[test]
    fn exhaustively_writes_every_byte_value_to_both_lanes() {
        for value in 0u16..=u8::MAX as u16 {
            let byte = value as u8;

            let mut low_word = [0xa500];
            write_byte(&mut low_word, LogicalByteAddress(0), byte).unwrap();
            assert_eq!(low_word[0], 0xa500 | value);

            let mut high_word = [0x005a];
            write_byte(&mut high_word, LogicalByteAddress(1), byte).unwrap();
            assert_eq!(high_word[0], 0x005a | (value << 8));
        }
    }
}

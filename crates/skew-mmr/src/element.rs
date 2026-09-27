pub trait Element: Clone + PartialEq {}

impl<T: Clone + PartialEq> Element for T {}

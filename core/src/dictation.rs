#[no_mangle]
pub extern "C" fn rium_dictation_selection_matches(
    start_location: i64,
    start_length: i64,
    current_location: i64,
    current_length: i64,
) -> i32 {
    i32::from(
        start_location >= 0
            && start_length >= 0
            && start_location.checked_add(start_length).is_some()
            && (start_location, start_length) == (current_location, current_length),
    )
}

#[repr(i32)]
#[derive(Debug, PartialEq, Eq)]
enum ModifierAction { Wait, Start, Finish, Cancel }

fn modifier_action(current: u64, required: u64, holding: bool, blocked: bool) -> ModifierAction {
    if current == 0 {
        return if holding { ModifierAction::Finish } else { ModifierAction::Wait };
    }
    if current & !required != 0 { return ModifierAction::Cancel; }
    if blocked { return ModifierAction::Wait; }
    match (holding, current == required) {
        (false, true) => ModifierAction::Start,
        (true, false) => ModifierAction::Finish,
        _ => ModifierAction::Wait,
    }
}

#[no_mangle]
pub extern "C" fn rium_dictation_modifier_action(current: u64, required: u64, holding: i32, blocked: i32) -> i32 {
    modifier_action(current, required, holding != 0, blocked != 0) as i32
}

#[cfg(test)]
mod tests {
    use super::rium_dictation_selection_matches as matches;
    use super::{modifier_action, ModifierAction::*};

    #[test]
    fn checks_cursor_selection_and_invalid_ax_ranges() {
        assert_eq!(matches(5, 0, 5, 0), 1);
        assert_eq!(matches(5, 2, 5, 2), 1);
        assert_eq!(matches(5, 2, 6, 2), 0);
        assert_eq!(matches(5, 2, 5, 0), 0);
        assert_eq!(matches(5, 2, -1, -1), 0);
        assert_eq!(matches(-1, -1, -1, -1), 0);
        assert_eq!(matches(5, -1, 5, -1), 0);
        assert_eq!(matches(i64::MAX, 1, i64::MAX, 1), 0);
    }

    #[test]
    fn modifier_actions_distinguish_release_from_an_interrupted_chord() {
        assert_eq!(modifier_action(1, 1, false, false), Start);
        assert_eq!(modifier_action(1, 1, true, false), Wait);
        assert_eq!(modifier_action(0, 1, true, false), Finish);
        assert_eq!(modifier_action(5, 1, true, false), Cancel);
        assert_eq!(modifier_action(5, 1, false, false), Cancel);
        assert_eq!(modifier_action(1, 1, false, true), Wait);
        assert_eq!(modifier_action(2, 3, false, false), Wait);
        assert_eq!(modifier_action(2, 3, true, false), Finish);
        assert_eq!(modifier_action(3, 3, false, true), Wait);
    }
}

use automerge::{AutoCommit, load_budget::{Limits, with_budget}};
fn main() {
    let path = std::env::args().nth(1).expect("fixture path");
    let data = std::fs::read(path).expect("read fixture");
    let result = with_budget(Limits::default(), || AutoCommit::load(&data));
    println!("{result:?}");
}
#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use automerge::load_budget::{inflate_into, charge_items};
    fn compressed(n: usize) -> Vec<u8> {
        let mut e = flate2::write::DeflateEncoder::new(Vec::new(), flate2::Compression::best());
        e.write_all(&vec![0; n]).unwrap(); e.finish().unwrap()
    }
    #[test] fn expansion_budget_boundary_and_cumulative() {
        let l = Limits { expanded_bytes: 4096, ..Limits::default() };
        assert!(with_budget(l.clone(), || inflate_into(&compressed(4096), &mut Vec::new())).unwrap().is_ok());
        assert!(with_budget(l.clone(), || inflate_into(&compressed(4097), &mut Vec::new())).is_err());
        assert!(with_budget(l.clone(), || { let mut v=Vec::new(); inflate_into(&compressed(2048), &mut v)?; inflate_into(&compressed(2049), &mut v) }).is_err());
    }
    #[test] fn item_budget_boundary() {
        let l = Limits { items: 3, ..Limits::default() };
        assert!(with_budget(l.clone(), || charge_items(3)).is_ok());
        assert!(with_budget(l.clone(), || charge_items(4)).is_err());
    }
    #[test] fn budget_scope_is_restored_on_failure_and_valid_document_loads() {
        assert!(with_budget(Limits { items: 0, ..Limits::default() }, || charge_items(1)).is_err());
        assert!(with_budget(Limits::default(), || charge_items(1)).is_ok());
        let mut document=AutoCommit::new();
        use automerge::transaction::Transactable;
        document.put(automerge::ROOT, "text", "é e\u{301}\r\n🦊").unwrap();
        let save=document.save();
        assert!(with_budget(Limits::default(), || AutoCommit::load(&save)).unwrap().is_ok());
    }
    #[test] fn operation_budget_and_cancelled_scope() {
        use automerge::load_budget::charge_operations;
        use std::sync::{Arc, atomic::AtomicBool};
        let limits=Limits { operations: 3, ..Limits::default() };
        assert!(with_budget(limits.clone(), || charge_operations(3)).is_ok());
        assert!(with_budget(limits, || charge_operations(4)).is_err());
        let cancelled=Arc::new(AtomicBool::new(true));
        assert!(with_budget(Limits { cancelled: Some(cancelled), ..Limits::default() }, || charge_items(0)).is_err());
    }

    #[test] fn nested_scope_cannot_reset_cumulative_limits() {
        assert!(with_budget(Limits::default(), || with_budget(Limits::default(), || charge_items(1))).is_err());
    }

    #[test] fn real_document_reconstruction_observes_operation_budget() {
        use automerge::transaction::Transactable;
        let mut doc=AutoCommit::new();
        for n in 0..10 {doc.put(automerge::ROOT, format!("field{n}"), n as i64).unwrap();}
        let saved=doc.save();
        assert!(with_budget(Limits {operations:3, ..Limits::default()}, || AutoCommit::load(&saved)).is_err());
        assert!(with_budget(Limits::default(), || AutoCommit::load(&saved)).unwrap().is_ok());
    }

}

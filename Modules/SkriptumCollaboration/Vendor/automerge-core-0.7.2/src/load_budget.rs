//! Scriptum experimental source-fork budgets. Not a complete allocator sandbox.
use std::{cell::RefCell, io::{self, Read}, time::{Duration, Instant}, sync::{Arc, atomic::{AtomicBool, Ordering}}};
#[derive(Clone, Debug)]
pub struct Limits {
    pub expanded_bytes: usize,
    pub allocated_bytes: usize,
    pub items: usize,
    pub row_values: usize,
    pub deadline_millis: u64,
    pub operations: usize,
    pub cancelled: Option<Arc<AtomicBool>>,
}
impl Default for Limits {
    fn default() -> Self { Self { expanded_bytes: 16*1024*1024, allocated_bytes: 64*1024*1024, items: 100_000, row_values: 2_000_000, deadline_millis: 500, operations:100_000, cancelled:None } }
}
struct State { limits: Limits, expanded: usize, allocated: usize, items: usize, rows: usize, operations:usize, started: Instant, failed: bool }
thread_local! { static STATE: RefCell<Option<State>> = const { RefCell::new(None) }; }
fn error() -> io::Error { io::Error::new(io::ErrorKind::InvalidData, "Scriptum resource budget exceeded") }
struct Scope(Option<State>);
impl Drop for Scope { fn drop(&mut self) { STATE.with(|cell| *cell.borrow_mut()=self.0.take()); } }
pub fn with_budget<T>(limits: Limits, action: impl FnOnce()->T) -> io::Result<T> {
    // One shared context per decode: reject nested scopes rather than allowing
    // a nested caller to replenish counters or extend the deadline.
    if STATE.with(|cell| { let mut current=cell.borrow_mut(); if let Some(s)=current.as_mut() {s.failed=true;true} else {false} }) {return Err(error())}
    let prior=STATE.with(|cell| cell.replace(Some(State {limits, expanded:0, allocated:0, items:0, rows:0, operations:0, started:Instant::now(), failed:false})));
    let scope=Scope(prior);
    let value=action();
    let failed=STATE.with(|cell| {let state=cell.borrow();let s=state.as_ref().unwrap();s.failed || s.started.elapsed()>Duration::from_millis(s.limits.deadline_millis) || s.limits.cancelled.as_ref().is_some_and(|c|c.load(Ordering::Relaxed))});
    drop(scope);
    if failed { Err(error()) } else { Ok(value) }
}
fn charge(which: u8, amount: usize) -> io::Result<()> {
    STATE.with(|cell| {
        let mut state=cell.borrow_mut(); let Some(s)=state.as_mut() else {return Ok(())};
        if s.failed || s.limits.cancelled.as_ref().is_some_and(|c|c.load(Ordering::Relaxed)) || s.started.elapsed() > Duration::from_millis(s.limits.deadline_millis) { s.failed=true; return Err(error()) }
        let (used,limit)=match which {0=>(&mut s.expanded,s.limits.expanded_bytes),1=>(&mut s.allocated,s.limits.allocated_bytes),2=>(&mut s.items,s.limits.items),3=>(&mut s.rows,s.limits.row_values),_=>(&mut s.operations,s.limits.operations)};
        match used.checked_add(amount) { Some(next) if next<=limit => {*used=next; Ok(())}, _=>{s.failed=true;Err(error())} }
    })
}
pub fn charge_items(amount: usize)->io::Result<()> {charge(2,amount)}
pub fn charge_operations(amount: usize)->io::Result<()> {charge(4,amount)}
pub fn charge_rows(amount: usize)->io::Result<()> {charge(3,amount)}
pub fn charge_allocation(amount: usize)->io::Result<()> {charge(1,amount)}
pub fn check_run(amount: usize)->io::Result<()> {
    STATE.with(|cell| { let mut state=cell.borrow_mut(); if let Some(s)=state.as_mut() { if amount>s.limits.row_values {s.failed=true;return Err(error())} } Ok(()) })
}
pub fn inflate_into(compressed: &[u8], out: &mut Vec<u8>)->io::Result<usize> {
    let mut decoder=flate2::bufread::DeflateDecoder::new(compressed);
    let mut buffer=[0_u8;8192]; let mut total=0usize;
    loop {
        charge_rows(0)?;
        let count=decoder.read(&mut buffer)?; if count==0 {return Ok(total)}
        charge(0,count)?; charge_allocation(count)?;
        total=total.checked_add(count).ok_or_else(error)?;
        out.try_reserve_exact(count).map_err(|_|error())?;
        out.extend_from_slice(&buffer[..count]);
    }
}

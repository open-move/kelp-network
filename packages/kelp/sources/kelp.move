module kelp::kelp;

use enclave::enclave::Enclave;
use std::string::String;
use sui::bcs;
use sui::derived_object;
use sui::url::Url;

public struct KELP() has drop;

const REPUTATION_DECIMALS: u64 = 1_000_000; // 6 decimal places
const INITIAL_REPUTATION: u64 = 1000 * REPUTATION_DECIMALS;
const MIN_REPUTATION: u64 = 100 * REPUTATION_DECIMALS;

const BPS_BASE: u64 = 10_000; // 100% = 10000 bps
const SLASH_RATE_BPS: u64 = 1000; // 10% slash on bad behavior

const CONSISTENCY_BPS_BASE: u64 = 10_000;

// Error codes
const EKelpManagerCapMismatch: u64 = 0;
const EInvalidEnclaveLayout: u64 = 1;
const EInvalidEnclaveOwner: u64 = 2;
const EReputationTooLow: u64 = 5;

public struct Kelp has key {
    id: UID,
    name: String,
    description: String,
    image_url: Url,
    enclave_id: ID,
    reputation: u64,
    submission_nonce: u64,
    consistency_score: u64,
    is_paused: bool,
    total_submissions: u64,
    successful_submissions: u64,
}

public struct Forest has key, store {
    id: UID,
    total_kelps: u64,
}

public struct KelpOperationCap has key, store {
    id: UID,
    kelp_id: ID,
}

public struct KelpManagerCap has key, store {
    id: UID,
    kelp_id: ID,
}

public struct KelpKey(u64) has copy, drop, store;
public struct KelpManagerKey() has copy, drop, store;
public struct KelpOperationKey() has copy, drop, store;

use fun enclave_owner as Enclave.owner;

public fun create(
    forest: &mut Forest,
    enclave: &Enclave<KELP>,
    name: String,
    description: String,
    image_url: Url,
    ctx: &TxContext,
): (Kelp, KelpManagerCap, KelpOperationCap) {
    assert!(enclave.owner() == ctx.sender(), EInvalidEnclaveOwner);

    let kelp = Kelp {
        id: derived_object::claim(&mut forest.id, KelpKey(forest.total_kelps)),
        name,
        image_url,
        description,
        is_paused: false,
        submission_nonce: 0,
        total_submissions: 0,
        successful_submissions: 0,
        reputation: INITIAL_REPUTATION,
        enclave_id: object::id(enclave),
        consistency_score: CONSISTENCY_BPS_BASE,
    };

    let manager_cap = KelpManagerCap {
        id: derived_object::claim(&mut forest.id, KelpManagerKey()),
        kelp_id: kelp.id.to_inner(),
    };

    let operation_cap = KelpOperationCap {
        id: derived_object::claim(&mut forest.id, KelpOperationKey()),
        kelp_id: kelp.id.to_inner(),
    };

    forest.total_kelps = forest.total_kelps + 1;
    (kelp, manager_cap, operation_cap)
}

public fun update_name(self: &mut Kelp, manager_cap: &KelpManagerCap, name: String) {
    assert!(self.id.to_inner() == manager_cap.kelp_id, EKelpManagerCapMismatch);
    self.name = name
}

public fun update_description(self: &mut Kelp, manager_cap: &KelpManagerCap, description: String) {
    assert!(self.id.to_inner() == manager_cap.kelp_id, EKelpManagerCapMismatch);
    self.description = description
}

public fun update_image_url(self: &mut Kelp, manager_cap: &KelpManagerCap, image_url: Url) {
    assert!(self.id.to_inner() == manager_cap.kelp_id, EKelpManagerCapMismatch);
    self.image_url = image_url
}

public fun update_enclave(
    self: &mut Kelp,
    manager_cap: &KelpManagerCap,
    enclave: &Enclave<KELP>,
    ctx: &TxContext,
) {
    assert!(self.id.to_inner() == manager_cap.kelp_id, EKelpManagerCapMismatch);
    assert!(enclave.owner() == ctx.sender(), EInvalidEnclaveOwner);
    self.enclave_id = object::id(enclave)
}

fun add_reputation(self: &mut Kelp, amount: u64) {
    self.reputation = self.reputation + amount;
}

fun slash_reputation(self: &mut Kelp) {
    let slashed = (self.reputation * SLASH_RATE_BPS) / BPS_BASE;
    self.reputation = self.reputation - slashed;
    if (self.reputation < MIN_REPUTATION) {
        self.is_paused = true;
    }
}

fun update_consistency(self: &mut Kelp, agreed_with_consensus: bool) {
    self.total_submissions = self.total_submissions + 1;
    if (agreed_with_consensus) {
        self.successful_submissions = self.successful_submissions + 1;
    };

    if (self.total_submissions > 0) {
        self.consistency_score =
            (self.successful_submissions * CONSISTENCY_BPS_BASE) / self.total_submissions;
    }
}

public fun pause(self: &mut Kelp, manager_cap: &KelpManagerCap) {
    assert!(self.id.to_inner() == manager_cap.kelp_id, EKelpManagerCapMismatch);
    self.is_paused = true;
}

public fun unpause(self: &mut Kelp, manager_cap: &KelpManagerCap) {
    assert!(self.id.to_inner() == manager_cap.kelp_id, EKelpManagerCapMismatch);
    assert!(self.reputation >= MIN_REPUTATION, EReputationTooLow);
    self.is_paused = false;
}

public fun reputation(self: &Kelp): u64 {
    self.reputation
}

public fun nonce(self: &Kelp): u64 {
    self.submission_nonce
}

public fun consistency_score_bps(self: &Kelp): u64 {
    self.consistency_score
}

public fun is_active(self: &Kelp): bool {
    !self.is_paused
}

public fun has_min_reputation(self: &Kelp): bool {
    self.reputation >= MIN_REPUTATION
}

public fun is_eligible(self: &Kelp): bool {
    !self.is_paused && self.has_min_reputation()
}

public fun enclave_id(self: &Kelp): ID {
    self.enclave_id
}

public fun name(self: &Kelp): String {
    self.name
}

public fun description(self: &Kelp): String {
    self.description
}

/// Mysten enclave package doesn’t expose a public getter for the owner of an enclave.
/// For now, we get it manually by decoding the object’s BCS layout.
fun enclave_owner(enclave: &Enclave<KELP>): address {
    let mut bcs = bcs::new(bcs::to_bytes(enclave));

    bcs.peel_address(); // UID -> object ID
    bcs.peel_vec_u8(); // pk
    bcs.peel_u64(); // config_version

    let owner = bcs.peel_address(); // owner
    assert!(bcs.into_remainder_bytes().is_empty(), EInvalidEnclaveLayout);
    owner
}

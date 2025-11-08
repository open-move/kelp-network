module kelp::kelp;

use enclave::enclave::Enclave;
use std::string::String;
use sui::derived_object;
use sui::url::Url;
use sui::bcs;

public struct KELP() has drop;

public struct Kelp has key {
    id: UID,
    name: String,
    description: String,
    image_url: Url,
    current_enclave_id: ID,
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

const EKelpManagerCapMismatch: u64 = 0;
const EInvalidEnclaveLayout: u64 = 1;
const EInvalidEnclaveOwner: u64 = 2;

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
        current_enclave_id: object::id(enclave),
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

public fun update_name(kelp: &mut Kelp, manager_cap: &KelpManagerCap, name: String) {
    assert!(kelp.id.to_inner() == manager_cap.kelp_id, EKelpManagerCapMismatch);
    kelp.name = name
}

public fun update_description(kelp: &mut Kelp, manager_cap: &KelpManagerCap, description: String) {
    assert!(kelp.id.to_inner() == manager_cap.kelp_id, EKelpManagerCapMismatch);
    kelp.description = description
}

public fun update_image_url(kelp: &mut Kelp, manager_cap: &KelpManagerCap, image_url: Url) {
    assert!(kelp.id.to_inner() == manager_cap.kelp_id, EKelpManagerCapMismatch);
    kelp.image_url = image_url
}

public fun update_enclave(kelp: &mut Kelp, manager_cap: &KelpManagerCap, enclave: &Enclave<KELP>) {
    assert!(kelp.id.to_inner() == manager_cap.kelp_id, EKelpManagerCapMismatch);
    kelp.current_enclave_id = object::id(enclave)
}

/// Mysten enclave package doesn’t expose a public getter for the owner of an enclave. 
/// For now, we get it manually by decoding the object’s BCS layout.
fun enclave_owner(enclave: &Enclave<KELP>): address {
    let mut bcs = bcs::new(bcs::to_bytes(enclave));

    bcs.peel_address();      // UID -> object ID
    bcs.peel_vec_u8();       // pk
    bcs.peel_u64();          // config_version

    let owner = bcs.peel_address(); // owner
    assert!(bcs.into_remainder_bytes().is_empty(), EInvalidEnclaveLayout);
    owner
}

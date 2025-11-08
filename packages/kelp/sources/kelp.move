module kelp::kelp;

use enclave::enclave::Enclave;
use std::string::String;
use sui::derived_object;
use sui::url::Url;

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

const EKelpManagerCapMismatch: u64 = 0;

public fun create(
    forest: &mut Forest,
    enclave: &Enclave<KELP>,
    name: String,
    description: String,
    image_url: Url,
    _ctx: &TxContext,
): (Kelp, KelpManagerCap, KelpOperationCap) {
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

/// Keeps customer-directory controls pinned while only customer cards scroll.
/// Other user lists preserve their existing header-with-content scroll behavior.
bool shouldPinUserListHeader(String role) => role.trim() == 'customer';

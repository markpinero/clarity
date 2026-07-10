public protocol DisplayDriver: AnyObject {
  func enumerateDisplays() throws -> [DisplayDescriptor]
  func captureTransferTable(for display: DisplayIdentifier) throws -> RGBTransferTable
  func apply(_ table: RGBTransferTable, to display: DisplayIdentifier) throws
}

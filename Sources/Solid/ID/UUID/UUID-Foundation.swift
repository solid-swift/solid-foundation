//
//  UUID-Foundation.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/23/25.
//

import Foundation


public extension UUID {

  @inlinable init(_ foundation: Foundation.UUID) {
    self.init(
      storage: Storage { span in
        Swift.withUnsafeBytes(of: foundation.uuid) { raw in
          for idx in 0..<raw.count {
            span.append(raw[idx])
          }
        }
      }
    )
  }

  @inlinable var foundation: Foundation.UUID {
    return Foundation.UUID(
      uuid: (
        storage[0], storage[1], storage[2], storage[3], storage[4], storage[5], storage[6], storage[7],
        storage[8], storage[9], storage[10], storage[11], storage[12], storage[13], storage[14], storage[15]
      )
    )
  }

}

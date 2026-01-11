//
//  SchemaMacros.swift
//  SolidFoundation
//
//  Created by Warp on 12/24/25.
//

@attached(member)
public macro SchemaCodable() = #externalMacro(module: "SolidCodingMacros", type: "SchemaCodableMacro")

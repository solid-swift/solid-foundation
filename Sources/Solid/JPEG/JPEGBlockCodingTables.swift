struct JPEGBlockCodingTables {
  let quantization: [Int]
  let dc: JPEGHuffmanCodec
  let ac: JPEGHuffmanCodec
}

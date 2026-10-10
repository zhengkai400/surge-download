import Foundation
@main struct DHTCacheTests {
    static func main() {
        func table(unique: Bool) -> Data {
            var d = Data([0xa1,0xa2,2,0,0,0,0,3]); d.append(Data(repeating:0,count:40)); d.append(Data([0,0,0,8])); d.append(Data(repeating:0,count:4))
            for i in 0..<8 {
                var r=Data(repeating:0,count:56); r[0]=6; r[8]=8; r[9]=8; r[10]=8; r[11]=UInt8(unique ? i+1 : 1); r[12]=26; r[13]=225
                r[32]=UInt8(unique ? i+1 : 1); d.append(r)
            }
            return d
        }
        precondition(!DHTBootstrap.validCache(Data()))
        precondition(!DHTBootstrap.validCache(table(unique:false)))
        precondition(DHTBootstrap.validCache(table(unique:true)))
        var corrupt=table(unique:true); corrupt[0]=0
        precondition(!DHTBootstrap.validCache(corrupt))
        precondition(!DHTBootstrap.validCache(table(unique:true).dropLast()))
        print("PASS: empty / duplicated / unique / invalid header / truncated cache")
    }
}

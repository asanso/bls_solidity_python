pragma solidity ^0.5.15;
import {BN256G2} from "https://github.com/musalbas/solidity-BN256G2/blob/master/BN256G2.sol";
library BLS {
    // Field order
    uint256 constant N = 21888242871839275222246405745257275088696311157297823662689037894645226208583;

    // curve order
    uint256 constant r = 21888242871839275222246405745257275088548364400416034343698204186575808495617;
    
    // Negated genarator of G2
    uint256 constant nG2x1 = 11559732032986387107991004021392285783925812861821192530917403151452391805634;
    uint256 constant nG2x0 = 10857046999023057135944570762232829481370756359578518086990519993285655852781;
    uint256 constant nG2y1 = 17805874995975841540914202342111839520379459829704422454583296818431106115052;
    uint256 constant nG2y0 = 13392588948715843804641432497768002650278120570034223513918757245338268106653;

    uint256 constant FIELD_MASK = 0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    uint256 constant SIGN_MASK = 0x8000000000000000000000000000000000000000000000000000000000000000;
    uint256 constant ODD_NUM = 0x8000000000000000000000000000000000000000000000000000000000000000;

    //eps^((p-1)/3)
    uint256 internal constant epsExp0x0 = 21575463638280843010398324269430826099269044274347216827212613867836435027261;
    uint256 internal constant epsExp0x1 = 10307601595873709700152284273816112264069230130616436755625194854815875713954;

    //eps^((p-1)/2)
    uint256 internal constant epsExp1x0 = 2821565182194536844548159561693502659359617185244120367078079554186484126554;
    uint256 internal constant epsExp1x1 = 3505843767911556378687030309984248845540243509899259641013678093033130930403;


    function verifySingle(
        uint256[2] memory signature,
        uint256[4] memory pubkey,
        uint256[2] memory message
    ) internal view returns (bool) {
        uint256[12] memory input = [
            signature[0],
            signature[1],
            nG2x1,
            nG2x0,
            nG2y1,
            nG2y0,
            message[0],
            message[1],
            pubkey[1],
            pubkey[0],
            pubkey[3],
            pubkey[2]
        ];
        uint256[1] memory out;
        bool success;
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            success := staticcall(sub(gas(), 2000), 8, input, 384, out, 0x20)
            switch success
                case 0 {
                    invalid()
                }
        }
        require(success, "");
        return out[0] != 0;
    }

    function verifyMultiple(
        uint256[2] memory signature,
        uint256[4][] memory pubkeys,
        uint256[2][] memory messages
    ) internal view returns (bool) {
        uint256 size = pubkeys.length;
        require(size > 0, "BLS: number of public key is zero");
        require(
            size == messages.length,
            "BLS: number of public keys and messages must be equal"
        );
        uint256 inputSize = (size + 1) * 6;
        uint256[] memory input = new uint256[](inputSize);
        input[0] = signature[0];
        input[1] = signature[1];
        input[2] = nG2x1;
        input[3] = nG2x0;
        input[4] = nG2y1;
        input[5] = nG2y0;
        for (uint256 i = 0; i < size; i++) {
            input[i * 6 + 6] = messages[i][0];
            input[i * 6 + 7] = messages[i][1];
            input[i * 6 + 8] = pubkeys[i][1];
            input[i * 6 + 9] = pubkeys[i][0];
            input[i * 6 + 10] = pubkeys[i][3];
            input[i * 6 + 11] = pubkeys[i][2];
        }
        uint256[1] memory out;
        bool success;
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            success := staticcall(
                sub(gas(), 2000),
                8,
                add(input, 0x20),
                mul(inputSize, 0x20),
                out,
                0x20
            )
            switch success
                case 0 {
                    invalid()
                }
        }
        require(success, "");
        return out[0] != 0;
    }

    function hashToPoint(bytes memory data)
        internal
        view
        returns (uint256[2] memory p)
    {
        return mapToPoint(keccak256(data));
    }

    function mapToPoint(bytes32 _x)
        internal
        view
        returns (uint256[2] memory p)
    {
        uint256 x = uint256(_x) % N;
        uint256 y;
        bool found = false;
        while (true) {
            y = mulmod(x, x, N);
            y = mulmod(y, x, N);
            y = addmod(y, 3, N);
            (y, found) = sqrt(y);
            if (found) {
                p[0] = x;
                p[1] = y;
                break;
            }
            x = addmod(x, 1, N);
        }
    }

    function isValidPublicKey(uint256[4] memory publicKey)
        internal
        pure
        returns (bool)
    {
        if (
            (publicKey[0] >= N) ||
            (publicKey[1] >= N) ||
            (publicKey[2] >= N || (publicKey[3] >= N))
        ) {
            return false;
        } else {
            return isOnCurveG2(publicKey);
        }
    }

    function isValidSignature(uint256[2] memory signature)
        internal
        pure
        returns (bool)
    {
        if ((signature[0] >= N) || (signature[1] >= N)) {
            return false;
        } else {
            return isOnCurveG1(signature);
        }
    }

    function pubkeyToUncompresed(
        uint256[2] memory compressed,
        uint256[2] memory y
    ) internal pure returns (uint256[4] memory uncompressed) {
        uint256 desicion = compressed[0] & SIGN_MASK;
        require(
            desicion == ODD_NUM || y[0] & 1 != 1,
            "BLS: bad y coordinate for uncompressing key"
        );
        uncompressed[0] = compressed[0] & FIELD_MASK;
        uncompressed[1] = compressed[1];
        uncompressed[2] = y[0];
        uncompressed[3] = y[1];
    }

    function signatureToUncompresed(uint256 compressed, uint256 y)
        internal
        pure
        returns (uint256[2] memory uncompressed)
    {
        uint256 desicion = compressed & SIGN_MASK;
        require(
            desicion == ODD_NUM || y & 1 != 1,
            "BLS: bad y coordinate for uncompressing key"
        );
        return [compressed & FIELD_MASK, y];
    }

    function isValidCompressedPublicKey(uint256[2] memory publicKey)
        internal
        view
        returns (bool)
    {
        uint256 x0 = publicKey[0] & FIELD_MASK;
        uint256 x1 = publicKey[1];
        if ((x0 >= N) || (x1 >= N)) {
            return false;
        } else if ((x0 == 0) && (x1 == 0)) {
            return false;
        } else {
            return isOnCurveG2([x0, x1]);
        }
    }

    function isValidCompressedSignature(uint256 signature)
        internal
        view
        returns (bool)
    {
        uint256 x = signature & FIELD_MASK;
        if (x >= N) {
            return false;
        } else if (x == 0) {
            return false;
        }
        return isOnCurveG1(x);
    }

    function isOnCurveG1(uint256[2] memory point)
        internal
        pure
        returns (bool _isOnCurve)
    {
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            let t0 := mload(point)
            let t1 := mload(add(point, 32))
            let t2 := mulmod(t0, t0, N)
            t2 := mulmod(t2, t0, N)
            t2 := addmod(t2, 3, N)
            t1 := mulmod(t1, t1, N)
            _isOnCurve := eq(t1, t2)
        }
    }

    function isOnCurveG1(uint256 x) internal view returns (bool _isOnCurve) {
        bool callSuccess;
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            let t0 := x
            let t1 := mulmod(t0, t0, N)
            t1 := mulmod(t1, t0, N)
            t1 := addmod(t1, 3, N)

            let freemem := mload(0x40)
            mstore(freemem, 0x20)
            mstore(add(freemem, 0x20), 0x20)
            mstore(add(freemem, 0x40), 0x20)
            mstore(add(freemem, 0x60), t1)
            // (N - 1) / 2 = 0x183227397098d014dc2822db40c0ac2ecbc0b548b438e5469e10460b6c3e7ea3
            mstore(
                add(freemem, 0x80),
                0x183227397098d014dc2822db40c0ac2ecbc0b548b438e5469e10460b6c3e7ea3
            )
            // N = 0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47
            mstore(
                add(freemem, 0xA0),
                0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47
            )
            callSuccess := staticcall(
                sub(gas(), 2000),
                5,
                freemem,
                0xC0,
                freemem,
                0x20
            )
            _isOnCurve := eq(1, mload(freemem))
        }
    }

    function isOnCurveG2(uint256[4] memory point)
        internal
        pure
        returns (bool _isOnCurve)
    {
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            // x0, x1
            let t0 := mload(point)
            let t1 := mload(add(point, 32))
            // x0 ^ 2
            let t2 := mulmod(t0, t0, N)
            // x1 ^ 2
            let t3 := mulmod(t1, t1, N)
            // 3 * x0 ^ 2
            let t4 := add(add(t2, t2), t2)
            // 3 * x1 ^ 2
            let t5 := addmod(add(t3, t3), t3, N)
            // x0 * (x0 ^ 2 - 3 * x1 ^ 2)
            t2 := mulmod(add(t2, sub(N, t5)), t0, N)
            // x1 * (3 * x0 ^ 2 - x1 ^ 2)
            t3 := mulmod(add(t4, sub(N, t3)), t1, N)

            // x ^ 3 + b
            t0 := addmod(
                t2,
                0x2b149d40ceb8aaae81be18991be06ac3b5b4c5e559dbefa33267e6dc24a138e5,
                N
            )
            t1 := addmod(
                t3,
                0x009713b03af0fed4cd2cafadeed8fdf4a74fa084e52d1852e4a2bd0685c315d2,
                N
            )

            // y0, y1
            t2 := mload(add(point, 64))
            t3 := mload(add(point, 96))
            // y ^ 2
            t4 := mulmod(addmod(t2, t3, N), addmod(t2, sub(N, t3), N), N)
            t3 := mulmod(shl(1, t2), t3, N)

            // y ^ 2 == x ^ 3 + b
            _isOnCurve := and(eq(t0, t4), eq(t1, t3))
        }
    }

    function isOnCurveG2(uint256[2] memory x)
        internal
        view
        returns (bool _isOnCurve)
    {
        bool callSuccess;
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            // x0, x1
            let t0 := mload(add(x, 0))
            let t1 := mload(add(x, 32))
            // x0 ^ 2
            let t2 := mulmod(t0, t0, N)
            // x1 ^ 2
            let t3 := mulmod(t1, t1, N)
            // 3 * x0 ^ 2
            let t4 := add(add(t2, t2), t2)
            // 3 * x1 ^ 2
            let t5 := addmod(add(t3, t3), t3, N)
            // x0 * (x0 ^ 2 - 3 * x1 ^ 2)
            t2 := mulmod(add(t2, sub(N, t5)), t0, N)
            // x1 * (3 * x0 ^ 2 - x1 ^ 2)
            t3 := mulmod(add(t4, sub(N, t3)), t1, N)
            // x ^ 3 + b
            t0 := add(
                t2,
                0x2b149d40ceb8aaae81be18991be06ac3b5b4c5e559dbefa33267e6dc24a138e5
            )
            t1 := add(
                t3,
                0x009713b03af0fed4cd2cafadeed8fdf4a74fa084e52d1852e4a2bd0685c315d2
            )

            // is non residue ?
            t0 := addmod(mulmod(t0, t0, N), mulmod(t1, t1, N), N)
            let freemem := mload(0x40)
            mstore(freemem, 0x20)
            mstore(add(freemem, 0x20), 0x20)
            mstore(add(freemem, 0x40), 0x20)
            mstore(add(freemem, 0x60), t0)
            // (N - 1) / 2 = 0x183227397098d014dc2822db40c0ac2ecbc0b548b438e5469e10460b6c3e7ea3
            mstore(
                add(freemem, 0x80),
                0x183227397098d014dc2822db40c0ac2ecbc0b548b438e5469e10460b6c3e7ea3
            )
            // N = 0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47
            mstore(
                add(freemem, 0xA0),
                0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47
            )
            callSuccess := staticcall(
                sub(gas(), 2000),
                5,
                freemem,
                0xC0,
                freemem,
                0x20
            )
            _isOnCurve := eq(1, mload(freemem))
        }
    }

    function isOnSubgroupG2Naive(uint256[4] memory point)
        internal
        view
        returns (bool)
    {
        uint256 t0;
        uint256 t1;
        uint256 t2;
        uint256 t3;
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            t0 := mload(add(point, 0))
            t1 := mload(add(point, 32))
            // y0, y1
            t2 := mload(add(point, 64))
            t3 := mload(add(point, 96))
        }
        uint256 xx;
        uint256 xy;
        uint256 yx;
        uint256 yy;

        (xx,xy,yx,yy) = BN256G2.ECTwistMul(r,t0,t1,t2,t3);
        return xx ==0  && xy==0 && yx==0  && yy==0;
    }

    function isNonResidueFP(uint256 e)
        internal
        view
        returns (bool isNonResidue)
    {
        bool callSuccess;
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            let freemem := mload(0x40)
            mstore(freemem, 0x20)
            mstore(add(freemem, 0x20), 0x20)
            mstore(add(freemem, 0x40), 0x20)
            mstore(add(freemem, 0x60), e)
            // (N - 1) / 2 = 0x183227397098d014dc2822db40c0ac2ecbc0b548b438e5469e10460b6c3e7ea3
            mstore(
                add(freemem, 0x80),
                0x183227397098d014dc2822db40c0ac2ecbc0b548b438e5469e10460b6c3e7ea3
            )
            // N = 0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47
            mstore(
                add(freemem, 0xA0),
                0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47
            )
            callSuccess := staticcall(
                sub(gas(), 2000),
                5,
                freemem,
                0xC0,
                freemem,
                0x20
            )
            isNonResidue := eq(1, mload(freemem))
        }
        require(callSuccess, "BLS: isNonResidueFP modexp call failed");
        return !isNonResidue;
    }

    function isNonResidueFP2(uint256[2] memory e)
        internal
        view
        returns (bool isNonResidue)
    {
        uint256 a = addmod(mulmod(e[0], e[0], N), mulmod(e[1], e[1], N), N);
        bool callSuccess;
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            let freemem := mload(0x40)
            mstore(freemem, 0x20)
            mstore(add(freemem, 0x20), 0x20)
            mstore(add(freemem, 0x40), 0x20)
            mstore(add(freemem, 0x60), a)
            // (N - 1) / 2 = 0x183227397098d014dc2822db40c0ac2ecbc0b548b438e5469e10460b6c3e7ea3
            mstore(
                add(freemem, 0x80),
                0x183227397098d014dc2822db40c0ac2ecbc0b548b438e5469e10460b6c3e7ea3
            )
            // N = 0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47
            mstore(
                add(freemem, 0xA0),
                0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47
            )
            callSuccess := staticcall(
                sub(gas(), 2000),
                5,
                freemem,
                0xC0,
                freemem,
                0x20
            )
            isNonResidue := eq(1, mload(freemem))
        }
        require(callSuccess, "BLS: isNonResidueFP2 modexp call failed");
        return !isNonResidue;
    }

    function sqrt(uint256 xx) internal view returns (uint256 x, bool hasRoot) {
        bool callSuccess;
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            let freemem := mload(0x40)
            mstore(freemem, 0x20)
            mstore(add(freemem, 0x20), 0x20)
            mstore(add(freemem, 0x40), 0x20)
            mstore(add(freemem, 0x60), xx)
            // (N + 1) / 4 = 0xc19139cb84c680a6e14116da060561765e05aa45a1c72a34f082305b61f3f52
            mstore(
                add(freemem, 0x80),
                0xc19139cb84c680a6e14116da060561765e05aa45a1c72a34f082305b61f3f52
            )
            // N = 0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47
            mstore(
                add(freemem, 0xA0),
                0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47
            )
            callSuccess := staticcall(
                sub(gas(), 2000),
                5,
                freemem,
                0xC0,
                freemem,
                0x20
            )
            x := mload(freemem)
            hasRoot := eq(xx, mulmod(x, x, N))
        }
        require(callSuccess, "BLS: sqrt modexp call failed");
    }

    function submod(uint256 a, uint256 b, uint256 n) internal pure returns (uint256) {
        return addmod(a, n - b, n);
    }

    function _FQ2Mul(
        uint256 xx, uint256 xy,
        uint256 yx, uint256 yy
    ) internal pure returns (uint256, uint256) {
        return (
            submod(mulmod(xx, yx, N), mulmod(xy, yy, N), N),
            addmod(mulmod(xx, yy, N), mulmod(xy, yx, N), N)
        );
    }

    function _FQ2Conjugate(
        uint256 x, uint256 y
    ) internal pure returns (uint256, uint256) {
        return (x, N-y);
    }

    function endomorphism(uint256 xx, uint256 xy,
        uint256 yx, uint256 yy) internal pure returns (uint256, uint256,uint256, uint256) {

        // Frobenius x coordinate
        (uint256 xxp,uint256 xyp) = _FQ2Conjugate(xx,xy);
        // Frobenius y coordinate
        (uint256 yxp,uint256 yyp) = _FQ2Conjugate(yx,yy);
        // x coordinate endomorphism
        (uint256 xxe,uint256 xye) = _FQ2Mul(epsExp0x0,epsExp0x1,xxp,xyp);
        // y coordinate endomorphism
        (uint256 yxe,uint256 yye) = _FQ2Mul(epsExp1x0, epsExp1x1,yxp,yyp);

        return (xxe,xye,yxe,yye);
    }
}

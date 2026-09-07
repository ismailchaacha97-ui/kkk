const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time, loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

const SUPPLY = ethers.parseEther("1000000000");
const ONE_PCT = SUPPLY / 100n;
const TWO_PCT = SUPPLY / 50n;

describe("Coo ($COO)", function () {
  async function deployFixture() {
    const [owner, treasury, alice, bob, pair] = await ethers.getSigners();
    const Coo = await ethers.getContractFactory("Coo");
    const coo = await Coo.deploy(treasury.address, owner.address);
    return { coo, owner, treasury, alice, bob, pair };
  }

  describe("metadata & supply", function () {
    it("has the right name, symbol and decimals", async function () {
      const { coo } = await loadFixture(deployFixture);
      expect(await coo.name()).to.equal("Sir Reginald Coo III");
      expect(await coo.symbol()).to.equal("COO");
      expect(await coo.decimals()).to.equal(18n);
    });

    it("mints exactly 1,000,000,000 to the treasury", async function () {
      const { coo, treasury } = await loadFixture(deployFixture);
      expect(await coo.totalSupply()).to.equal(SUPPLY);
      expect(await coo.balanceOf(treasury.address)).to.equal(SUPPLY);
    });

    it("exposes no mint function whatsoever", async function () {
      const { coo } = await loadFixture(deployFixture);
      const fns = coo.interface.fragments
        .filter((f) => f.type === "function")
        .map((f) => f.name.toLowerCase());
      expect(fns.some((n) => n.includes("mint"))).to.equal(false);
    });

    it("rejects a zero treasury or zero owner", async function () {
      const [owner] = await ethers.getSigners();
      const Coo = await ethers.getContractFactory("Coo");
      await expect(Coo.deploy(ethers.ZeroAddress, owner.address)).to.be.revertedWith(
        "COO: treasury is zero"
      );
      await expect(
        Coo.deploy(owner.address, ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(Coo, "OwnableInvalidOwner");
    });
  });

  describe("transfers are tax free", function () {
    it("delivers 100% of the amount sent", async function () {
      const { coo, treasury, alice } = await loadFixture(deployFixture);
      const amount = ethers.parseEther("1000");
      await coo.connect(treasury).transfer(alice.address, amount);
      expect(await coo.balanceOf(alice.address)).to.equal(amount);
    });

    it("conserves total supply across a transfer", async function () {
      const { coo, treasury, alice } = await loadFixture(deployFixture);
      await coo.connect(treasury).transfer(alice.address, ethers.parseEther("12345"));
      expect(await coo.totalSupply()).to.equal(SUPPLY);
    });
  });

  describe("anti-sniper max wallet", function () {
    it("starts at 2% of supply and is active", async function () {
      const { coo } = await loadFixture(deployFixture);
      expect(await coo.maxWallet()).to.equal(TWO_PCT);
      expect(await coo.limitsActive()).to.equal(true);
    });

    it("blocks a wallet from exceeding the cap", async function () {
      const { coo, treasury, alice } = await loadFixture(deployFixture);
      await expect(
        coo.connect(treasury).transfer(alice.address, TWO_PCT + 1n)
      ).to.be.revertedWithCustomError(coo, "MaxWalletExceeded");
    });

    it("allows exactly the cap", async function () {
      const { coo, treasury, alice } = await loadFixture(deployFixture);
      await coo.connect(treasury).transfer(alice.address, TWO_PCT);
      expect(await coo.balanceOf(alice.address)).to.equal(TWO_PCT);
    });

    it("ignores the cap for exempt addresses like the LP pair", async function () {
      const { coo, owner, treasury, pair } = await loadFixture(deployFixture);
      await coo.connect(owner).setLimitExempt(pair.address, true);
      await coo.connect(treasury).transfer(pair.address, SUPPLY / 2n);
      expect(await coo.balanceOf(pair.address)).to.equal(SUPPLY / 2n);
    });

    it("expires on its own after 24h even if the owner does nothing", async function () {
      const { coo, treasury, alice } = await loadFixture(deployFixture);
      await time.increase(24 * 60 * 60 + 1);
      expect(await coo.limitsActive()).to.equal(false);
      await coo.connect(treasury).transfer(alice.address, SUPPLY / 4n);
      expect(await coo.balanceOf(alice.address)).to.equal(SUPPLY / 4n);
    });

    it("cannot be lowered, only raised", async function () {
      const { coo, owner } = await loadFixture(deployFixture);
      await expect(coo.connect(owner).setMaxWallet(ONE_PCT)).to.be.revertedWithCustomError(
        coo,
        "CapCannotBeLowered"
      );
      await coo.connect(owner).setMaxWallet(SUPPLY / 10n);
      expect(await coo.maxWallet()).to.equal(SUPPLY / 10n);
    });

    it("cannot be set below 1% of supply", async function () {
      const { coo, owner } = await loadFixture(deployFixture);
      await expect(
        coo.connect(owner).setMaxWallet(ONE_PCT - 1n)
      ).to.be.revertedWithCustomError(coo, "CapTooLow");
    });

    it("removeLimits is a one-way door", async function () {
      const { coo, owner, treasury, alice } = await loadFixture(deployFixture);
      await expect(coo.connect(owner).removeLimits()).to.emit(coo, "LimitsRemovedForever");
      expect(await coo.maxWallet()).to.equal(0n);
      expect(await coo.limitsActive()).to.equal(false);
      await coo.connect(treasury).transfer(alice.address, SUPPLY / 3n);
      await expect(coo.connect(owner).setMaxWallet(TWO_PCT)).to.be.revertedWithCustomError(
        coo,
        "LimitsAlreadyRemoved"
      );
      await expect(coo.connect(owner).removeLimits()).to.be.revertedWithCustomError(
        coo,
        "LimitsAlreadyRemoved"
      );
    });

    it("is not callable by randoms", async function () {
      const { coo, alice } = await loadFixture(deployFixture);
      await expect(coo.connect(alice).removeLimits()).to.be.revertedWithCustomError(
        coo,
        "OwnableUnauthorizedAccount"
      );
      await expect(
        coo.connect(alice).setLimitExempt(alice.address, true)
      ).to.be.revertedWithCustomError(coo, "OwnableUnauthorizedAccount");
    });
  });

  describe("honeypot checks a scanner will run", function () {
    it("lets a fresh buyer sell straight back out", async function () {
      const { coo, owner, treasury, alice, pair } = await loadFixture(deployFixture);
      await coo.connect(owner).setLimitExempt(pair.address, true);
      await coo.connect(treasury).transfer(pair.address, SUPPLY / 2n);
      // "buy"
      await coo.connect(pair).transfer(alice.address, ethers.parseEther("500"));
      // "sell" — must not revert, must move the full amount
      await coo.connect(alice).transfer(pair.address, ethers.parseEther("500"));
      expect(await coo.balanceOf(alice.address)).to.equal(0n);
    });

    it("has no pause, blacklist or upgrade surface", async function () {
      const { coo } = await loadFixture(deployFixture);
      const fns = coo.interface.fragments
        .filter((f) => f.type === "function")
        .map((f) => f.name.toLowerCase());
      for (const banned of ["pause", "blacklist", "setfee", "settax", "upgradeto", "withdraw"]) {
        expect(fns.some((n) => n.includes(banned)), `found ${banned}`).to.equal(false);
      }
    });

    it("survives ownership renouncement — transfers still work", async function () {
      const { coo, owner, treasury, alice } = await loadFixture(deployFixture);
      await coo.connect(owner).removeLimits();
      await coo.connect(owner).renounceOwnership();
      expect(await coo.owner()).to.equal(ethers.ZeroAddress);
      await coo.connect(treasury).transfer(alice.address, ethers.parseEther("777"));
      expect(await coo.balanceOf(alice.address)).to.equal(ethers.parseEther("777"));
    });
  });

  describe("burn & permit", function () {
    it("burns supply for real", async function () {
      const { coo, treasury } = await loadFixture(deployFixture);
      const burn = ethers.parseEther("1000000");
      await coo.connect(treasury).burn(burn);
      expect(await coo.totalSupply()).to.equal(SUPPLY - burn);
    });

    it("supports EIP-2612 gasless approvals", async function () {
      const { coo, treasury, alice } = await loadFixture(deployFixture);
      const value = ethers.parseEther("100");
      const deadline = (await time.latest()) + 3600;
      const nonce = await coo.nonces(treasury.address);
      const domain = {
        name: "Sir Reginald Coo III",
        version: "1",
        chainId: (await ethers.provider.getNetwork()).chainId,
        verifyingContract: await coo.getAddress(),
      };
      const types = {
        Permit: [
          { name: "owner", type: "address" },
          { name: "spender", type: "address" },
          { name: "value", type: "uint256" },
          { name: "nonce", type: "uint256" },
          { name: "deadline", type: "uint256" },
        ],
      };
      const sig = await treasury.signTypedData(domain, types, {
        owner: treasury.address,
        spender: alice.address,
        value,
        nonce,
        deadline,
      });
      const { v, r, s } = ethers.Signature.from(sig);
      await coo.permit(treasury.address, alice.address, value, deadline, v, r, s);
      expect(await coo.allowance(treasury.address, alice.address)).to.equal(value);
    });
  });

  describe("ownership handover is two-step", function () {
    it("requires the new owner to accept", async function () {
      const { coo, owner, alice } = await loadFixture(deployFixture);
      await coo.connect(owner).transferOwnership(alice.address);
      expect(await coo.owner()).to.equal(owner.address); // not yet
      await coo.connect(alice).acceptOwnership();
      expect(await coo.owner()).to.equal(alice.address);
    });
  });
});

require('dotenv').config();
const express = require('express');
const cors = require('cors');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { Sequelize, DataTypes } = require('sequelize');
const path = require('path');
const crypto = require('crypto');
const Razorpay = require('razorpay');

const razorpay = new Razorpay({
  key_id: process.env.RAZORPAY_KEY_ID || 'rzp_test_mock',
  key_secret: process.env.RAZORPAY_KEY_SECRET || 'rzp_test_secret',
});

const app = express();

// Middleware
app.use(cors());
app.use(express.json());

// Serve static files from the React app (removed to prevent ENOENT crashes)
// app.use(express.static(path.join(__dirname, 'client', 'build')));

// Railway provides these environment variables
const PORT = process.env.PORT || process.env.RAILWAY_PUBLIC_PORT || 5000;
const HOST = process.env.HOST || '0.0.0.0';

// SQLite Connection
const sequelize = new Sequelize({
  dialect: 'sqlite',
  storage: path.join(__dirname, 'database.sqlite'),
  logging: false,
});

// Models configuration
const User = sequelize.define('User', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  email: { type: DataTypes.STRING, allowNull: false, unique: true },
  password: { type: DataTypes.STRING, allowNull: false },
  role: { type: DataTypes.STRING, defaultValue: 'resident' },
  name: { type: DataTypes.STRING, allowNull: false },
  apartmentNumber: { type: DataTypes.STRING },
  contactNumber: { type: DataTypes.STRING },
});

const Society = sequelize.define('Society', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  name: { type: DataTypes.STRING, allowNull: false },
  address: { type: DataTypes.STRING, allowNull: false },
  city: { type: DataTypes.STRING, allowNull: false },
  registrationNumber: { type: DataTypes.STRING },
  subscriptionStatus: { type: DataTypes.STRING, defaultValue: 'active' }, // active, suspended, pending
  subscriptionPlan: { type: DataTypes.STRING, defaultValue: 'basic' } // free, basic, premium
});

const Block = sequelize.define('Block', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  name: { type: DataTypes.STRING, allowNull: false },
});

const Flat = sequelize.define('Flat', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  number: { type: DataTypes.STRING, allowNull: false },
  floor: { type: DataTypes.INTEGER },
});

const Visitor = sequelize.define('Visitor', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  name: { type: DataTypes.STRING, allowNull: false },
  mobile: { type: DataTypes.STRING, allowNull: false },
  purpose: { type: DataTypes.STRING, allowNull: false },
  status: { type: DataTypes.STRING, defaultValue: 'Pending' }, // Pending, Approved, Denied, Entered, Exited
  expectedEntry: { type: DataTypes.DATE },
  actualEntry: { type: DataTypes.DATE },
  exitTime: { type: DataTypes.DATE },
  passCode: { type: DataTypes.STRING }
});

const MaintenanceRequest = sequelize.define('MaintenanceRequest', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  title: { type: DataTypes.STRING, allowNull: false },
  description: { type: DataTypes.STRING, allowNull: false },
  status: { type: DataTypes.STRING, defaultValue: 'pending' }, // pending, in_progress, resolved, escalated
  priority: { type: DataTypes.STRING, defaultValue: 'medium' }, // low, medium, high, critical
  category: { type: DataTypes.STRING, defaultValue: 'general' }, // plumbing, electrical, security, others
  slaDeadline: { type: DataTypes.DATE },
  escalatedAt: { type: DataTypes.DATE },
  resolvedAt: { type: DataTypes.DATE },
  residentRating: { type: DataTypes.INTEGER }, // 1-5
  residentComment: { type: DataTypes.STRING },
  societyId: { type: DataTypes.UUID }
});

const Event = sequelize.define('Event', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  title: { type: DataTypes.STRING, allowNull: false },
  description: { type: DataTypes.STRING },
  date: { type: DataTypes.DATE, allowNull: false },
  time: { type: DataTypes.STRING, allowNull: false },
  location: { type: DataTypes.STRING, allowNull: false },
});

const Invoice = sequelize.define('Invoice', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  title: { type: DataTypes.STRING, allowNull: false },
  amount: { type: DataTypes.FLOAT, allowNull: false },
  taxAmount: { type: DataTypes.FLOAT, defaultValue: 0 },
  totalAmount: { type: DataTypes.FLOAT, allowNull: false },
  status: { type: DataTypes.STRING, defaultValue: 'unpaid' }, // unpaid, paid, overdue
  dueDate: { type: DataTypes.DATE, allowNull: false },
});

const Payment = sequelize.define('Payment', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  amount: { type: DataTypes.FLOAT, allowNull: false },
  method: { type: DataTypes.STRING, defaultValue: 'UPI' },
  status: { type: DataTypes.STRING, defaultValue: 'pending' }, // pending, completed, failed
  paymentDate: { type: DataTypes.DATE },
  transactionId: { type: DataTypes.STRING }, // Razorpay payment ID
  razorpayOrderId: { type: DataTypes.STRING }, // Razorpay order ID
});

// Relationships
User.hasMany(MaintenanceRequest, { foreignKey: 'submittedById', as: 'submittedRequests' });
MaintenanceRequest.belongsTo(User, { foreignKey: 'submittedById', as: 'submittedBy' });

User.hasMany(MaintenanceRequest, { foreignKey: 'assignedToId', as: 'assignedRequests' });
MaintenanceRequest.belongsTo(User, { foreignKey: 'assignedToId', as: 'assignedTo' });

User.hasMany(Event, { foreignKey: 'organizerId', as: 'organizedEvents' });
Event.belongsTo(User, { foreignKey: 'organizerId', as: 'organizer' });

// Multi-Tenancy Relationships
Society.hasMany(Block, { foreignKey: 'societyId' });
Block.belongsTo(Society, { foreignKey: 'societyId' });

Block.hasMany(Flat, { foreignKey: 'blockId' });
Flat.belongsTo(Block, { foreignKey: 'blockId' });

Society.hasMany(Flat, { foreignKey: 'societyId' });
Flat.belongsTo(Society, { foreignKey: 'societyId' });

Flat.hasMany(User, { foreignKey: 'flatId' });
User.belongsTo(Flat, { foreignKey: 'flatId' });

Society.hasMany(User, { foreignKey: 'societyId' });
User.belongsTo(Society, { foreignKey: 'societyId' });

// Billing & Payments Relationships
User.hasMany(Invoice, { foreignKey: 'residentId' });
Invoice.belongsTo(User, { foreignKey: 'residentId' });

Society.hasMany(Invoice, { foreignKey: 'societyId' });
Invoice.belongsTo(Society, { foreignKey: 'societyId' });

Invoice.hasMany(Payment, { foreignKey: 'invoiceId' });
Payment.belongsTo(Invoice, { foreignKey: 'invoiceId' });

User.hasMany(Payment, { foreignKey: 'residentId' });
Payment.belongsTo(User, { foreignKey: 'residentId' });

Society.hasMany(MaintenanceRequest, { foreignKey: 'societyId' });
MaintenanceRequest.belongsTo(Society, { foreignKey: 'societyId' });

// Visitor Relationships
Flat.hasMany(Visitor, { foreignKey: 'flatId' });
Visitor.belongsTo(Flat, { foreignKey: 'flatId' });

User.hasMany(Visitor, { foreignKey: 'approvedById' });
Visitor.belongsTo(User, { foreignKey: 'approvedById' });

Society.hasMany(Visitor, { foreignKey: 'societyId' });
Visitor.belongsTo(Society, { foreignKey: 'societyId' });

// --- PHASE 3 MODELS ---

// Daily Help (Maids, Cooks, Drivers, Watchmen etc.)
const DailyHelp = sequelize.define('DailyHelp', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  name: { type: DataTypes.STRING, allowNull: false },
  type: { type: DataTypes.STRING, allowNull: false }, // maid, cook, driver, watchman, other
  mobile: { type: DataTypes.STRING, allowNull: false },
  isActive: { type: DataTypes.BOOLEAN, defaultValue: true },
  workingDays: { type: DataTypes.STRING, defaultValue: 'Mon,Tue,Wed,Thu,Fri,Sat' }, // CSV
  entryTime: { type: DataTypes.STRING, defaultValue: '08:00' },
  exitTime: { type: DataTypes.STRING, defaultValue: '11:00' },
});

const HelpAttendance = sequelize.define('HelpAttendance', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  date: { type: DataTypes.DATEONLY, allowNull: false },
  status: { type: DataTypes.STRING, defaultValue: 'present' }, // present, absent, late
  checkIn: { type: DataTypes.STRING },
  checkOut: { type: DataTypes.STRING },
});

// Amenities (Club house, Gym, Pool, etc.)
const Amenity = sequelize.define('Amenity', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  name: { type: DataTypes.STRING, allowNull: false },
  description: { type: DataTypes.STRING },
  capacity: { type: DataTypes.INTEGER, defaultValue: 10 },
  pricePerHour: { type: DataTypes.FLOAT, defaultValue: 0 },
  openTime: { type: DataTypes.STRING, defaultValue: '06:00' },
  closeTime: { type: DataTypes.STRING, defaultValue: '22:00' },
  isAvailable: { type: DataTypes.BOOLEAN, defaultValue: true },
  imageEmoji: { type: DataTypes.STRING, defaultValue: '🏊' },
});

const AmenityBooking = sequelize.define('AmenityBooking', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  bookingDate: { type: DataTypes.DATEONLY, allowNull: false },
  startTime: { type: DataTypes.STRING, allowNull: false },
  endTime: { type: DataTypes.STRING, allowNull: false },
  status: { type: DataTypes.STRING, defaultValue: 'confirmed' }, // confirmed, cancelled, completed
  totalAmount: { type: DataTypes.FLOAT, defaultValue: 0 },
  notes: { type: DataTypes.STRING },
});

// --- PLATFORM MANAGEMENT (Super Admin) ---

const PlatformSetting = sequelize.define('PlatformSetting', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  key: { type: DataTypes.STRING, unique: true },
  value: { type: DataTypes.TEXT }, // Stores JSON strings
});

const PlatformInvoice = sequelize.define('PlatformInvoice', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  amount: { type: DataTypes.FLOAT, allowNull: false },
  status: { type: DataTypes.STRING, defaultValue: 'pending' }, // pending, paid, overdue
  billingCycle: { type: DataTypes.DATEONLY },
});

PlatformInvoice.belongsTo(Society, { foreignKey: 'societyId' });
Society.hasMany(PlatformInvoice, { foreignKey: 'societyId' });

// ... rest of relationships

// Phase 3 Relationships
Flat.hasMany(DailyHelp, { foreignKey: 'flatId' });
DailyHelp.belongsTo(Flat, { foreignKey: 'flatId' });

Society.hasMany(DailyHelp, { foreignKey: 'societyId' });
DailyHelp.belongsTo(Society, { foreignKey: 'societyId' });

DailyHelp.hasMany(HelpAttendance, { foreignKey: 'helpId' });
HelpAttendance.belongsTo(DailyHelp, { foreignKey: 'helpId' });

Society.hasMany(Amenity, { foreignKey: 'societyId' });
Amenity.belongsTo(Society, { foreignKey: 'societyId' });

Amenity.hasMany(AmenityBooking, { foreignKey: 'amenityId' });
AmenityBooking.belongsTo(Amenity, { foreignKey: 'amenityId' });

User.hasMany(AmenityBooking, { foreignKey: 'bookedById' });
AmenityBooking.belongsTo(User, { foreignKey: 'bookedById' });

// --- PHASE 4 MODELS ---

// Notice Board
const Notice = sequelize.define('Notice', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  title: { type: DataTypes.STRING, allowNull: false },
  body: { type: DataTypes.TEXT, allowNull: false },
  category: { type: DataTypes.STRING, defaultValue: 'general' }, // general, urgent, event, maintenance
  isPinned: { type: DataTypes.BOOLEAN, defaultValue: false },
});

// Community Polls
const Poll = sequelize.define('Poll', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  question: { type: DataTypes.STRING, allowNull: false },
  options: { type: DataTypes.TEXT, allowNull: false }, // JSON array stored as string
  endDate: { type: DataTypes.DATE, allowNull: false },
  isActive: { type: DataTypes.BOOLEAN, defaultValue: true },
});

const PollVote = sequelize.define('PollVote', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  optionIndex: { type: DataTypes.INTEGER, allowNull: false },
});

// Phase 4 Relationships
Society.hasMany(Notice, { foreignKey: 'societyId' });
Notice.belongsTo(Society, { foreignKey: 'societyId' });
User.hasMany(Notice, { foreignKey: 'postedById' });
Notice.belongsTo(User, { foreignKey: 'postedById', as: 'postedBy' });

Society.hasMany(Poll, { foreignKey: 'societyId' });
Poll.belongsTo(Society, { foreignKey: 'societyId' });
User.hasMany(Poll, { foreignKey: 'createdById' });
Poll.belongsTo(User, { foreignKey: 'createdById' });

Poll.hasMany(PollVote, { foreignKey: 'pollId' });
PollVote.belongsTo(Poll, { foreignKey: 'pollId' });
User.hasMany(PollVote, { foreignKey: 'userId' });
PollVote.belongsTo(User, { foreignKey: 'userId' });

// --- PHASE 5 MODELS ---

// Parking Management
const ParkingSlot = sequelize.define('ParkingSlot', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  slotNumber: { type: DataTypes.STRING, allowNull: false },
  type: { type: DataTypes.STRING, defaultValue: 'car' }, // car, bike, ev
  floor: { type: DataTypes.STRING, defaultValue: 'B1' },
  status: { type: DataTypes.STRING, defaultValue: 'available' }, // available, occupied, reserved
  vehicleNo: { type: DataTypes.STRING },
});

const ParkingAllocation = sequelize.define('ParkingAllocation', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  vehicleNo: { type: DataTypes.STRING, allowNull: false },
  vehicleType: { type: DataTypes.STRING, defaultValue: 'car' },
  startDate: { type: DataTypes.DATEONLY, allowNull: false },
  endDate: { type: DataTypes.DATEONLY },
  isActive: { type: DataTypes.BOOLEAN, defaultValue: true },
});

// Marketplace
const MarketplaceListing = sequelize.define('MarketplaceListing', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  title: { type: DataTypes.STRING, allowNull: false },
  description: { type: DataTypes.TEXT },
  price: { type: DataTypes.FLOAT, defaultValue: 0 },
  category: { type: DataTypes.STRING, defaultValue: 'other' }, // furniture, electronics, appliances, vehicle, services, other
  condition: { type: DataTypes.STRING, defaultValue: 'good' }, // new, good, fair, poor
  status: { type: DataTypes.STRING, defaultValue: 'active' }, // active, sold, removed
  imageEmoji: { type: DataTypes.STRING, defaultValue: '📦' },
  contactInfo: { type: DataTypes.STRING },
});

// Phase 5 Relationships
Society.hasMany(ParkingSlot, { foreignKey: 'societyId' });
ParkingSlot.belongsTo(Society, { foreignKey: 'societyId' });
Flat.hasMany(ParkingAllocation, { foreignKey: 'flatId' });
ParkingAllocation.belongsTo(Flat, { foreignKey: 'flatId' });
User.hasMany(ParkingAllocation, { foreignKey: 'allocatedById' });
ParkingAllocation.belongsTo(User, { foreignKey: 'allocatedById', as: 'allocatedBy' });
ParkingSlot.hasMany(ParkingAllocation, { foreignKey: 'slotId' });
ParkingAllocation.belongsTo(ParkingSlot, { foreignKey: 'slotId' });

Society.hasMany(MarketplaceListing, { foreignKey: 'societyId' });
MarketplaceListing.belongsTo(Society, { foreignKey: 'societyId' });
User.hasMany(MarketplaceListing, { foreignKey: 'sellerId' });
MarketplaceListing.belongsTo(User, { foreignKey: 'sellerId', as: 'seller' });

// --- IN-APP NOTIFICATIONS MODEL ---
const AppNotification = sequelize.define('AppNotification', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  title: { type: DataTypes.STRING, allowNull: false },
  body: { type: DataTypes.STRING, allowNull: false },
  type: { type: DataTypes.STRING, defaultValue: 'general' }, // visitor, payment, maintenance, notice, amenity, general
  isRead: { type: DataTypes.BOOLEAN, defaultValue: false },
});

// Notification Relationships
User.hasMany(AppNotification, { foreignKey: 'userId' });
AppNotification.belongsTo(User, { foreignKey: 'userId' });
Society.hasMany(AppNotification, { foreignKey: 'societyId' });
AppNotification.belongsTo(Society, { foreignKey: 'societyId' });

// Helper: create a notification for a specific user
async function createNotification(userId, societyId, title, body, type = 'general') {
  try {
    await AppNotification.create({ userId, societyId, title, body, type });
  } catch (e) {
    console.error('Failed to create notification:', e.message);
  }
}

sequelize.sync({ force: false }).then(async () => {
  console.log('Database synchronized.');
  
  // Seed a default Society and block for testing if none exist
  const societyCount = await Society.count();
  let defaultSocietyId;
  if (societyCount === 0) {
    const society = await Society.create({
      name: 'Grand Omaxe',
      address: 'Sector 93B',
      city: 'Noida',
      registrationNumber: 'GO-12345'
    });
    defaultSocietyId = society.id;
    const block = await Block.create({ name: 'Tower A', societyId: society.id });
    await Flat.create({ number: '101', floor: 1, blockId: block.id, societyId: society.id });
    console.log('Seeded default Society, Block, and Flat.');
  } else {
    const society = await Society.findOne();
    defaultSocietyId = society.id;
  }

  // Seed default admin and invoice for testing
  const adminCount = await User.count({ where: { role: 'admin' } });
  if (adminCount === 0) {
    const hashed = await bcrypt.hash('admin123', 8);
    const admin = await User.create({ email: 'admin@society.com', password: hashed, name: 'Admin', role: 'admin', societyId: defaultSocietyId });
    // create resident
    const resHashed = await bcrypt.hash('password123', 8);
    const resident = await User.create({ email: 'resident@society.com', password: resHashed, name: 'John Doe', role: 'resident', societyId: defaultSocietyId });
    
    // Create an invoice
    await Invoice.create({
      title: 'April Maintenance',
      amount: 4500,
      taxAmount: 810,
      totalAmount: 5310,
      dueDate: new Date(new Date().setMonth(new Date().getMonth() + 1)),
      residentId: resident.id,
      societyId: defaultSocietyId,
      status: 'unpaid'
    });
    console.log('Seeded admin, resident, and invoice.');
  }

  // Seed default super admin
  const superAdminCount = await User.count({ where: { role: 'super_admin' } });
  if (superAdminCount === 0) {
    const hashedSA = await bcrypt.hash('superadmin123', 8);
    await User.create({ email: 'superadmin@societyhub.com', password: hashedSA, name: 'SaaS Platform Admin', role: 'super_admin' });
    console.log('Seeded super_admin.');
  }

  // Seed default amenities
  const amenityCount = await Amenity.count();
  if (amenityCount === 0) {
    await Amenity.bulkCreate([
      { name: 'Swimming Pool', description: 'Olympic size heated pool', capacity: 20, pricePerHour: 200, openTime: '06:00', closeTime: '21:00', imageEmoji: '🏊', societyId: defaultSocietyId },
      { name: 'Gym', description: 'Fully equipped gymnasium', capacity: 15, pricePerHour: 0, openTime: '05:00', closeTime: '23:00', imageEmoji: '🏋️', societyId: defaultSocietyId },
      { name: 'Clubhouse', description: 'Multi-purpose hall for events', capacity: 100, pricePerHour: 1500, openTime: '08:00', closeTime: '22:00', imageEmoji: '🏛️', societyId: defaultSocietyId },
      { name: 'Tennis Court', description: 'Outdoor tennis court with floodlights', capacity: 4, pricePerHour: 300, openTime: '06:00', closeTime: '21:00', imageEmoji: '🎾', societyId: defaultSocietyId },
      { name: 'Kids Play Area', description: 'Safe outdoor play zone for children', capacity: 30, pricePerHour: 0, openTime: '07:00', closeTime: '20:00', imageEmoji: '🛝', societyId: defaultSocietyId },
    ]);
    console.log('Seeded default Amenities.');
  }

  // Seed default notices
  const noticeCount = await Notice.count();
  if (noticeCount === 0 && defaultSocietyId) {
    const admin = await User.findOne({ where: { role: 'admin' } });
    if (admin) {
      await Notice.bulkCreate([
        { title: '🎉 Welcome to SecureGate!', body: 'We are delighted to launch our new society management platform. Enjoy seamless access control, payments, and community features.', category: 'general', isPinned: true, societyId: defaultSocietyId, postedById: admin.id },
        { title: '⚠️ Water Supply Disruption', body: 'Water supply will be interrupted on Saturday 29th March from 10 AM to 2 PM for pipeline maintenance. Please store accordingly.', category: 'urgent', isPinned: false, societyId: defaultSocietyId, postedById: admin.id },
        { title: '🎊 Holi Celebration', body: 'Join us for the Holi celebration in the clubhouse on March 30th at 9 AM. Colors, gulal, music and breakfast included!', category: 'event', isPinned: false, societyId: defaultSocietyId, postedById: admin.id },
      ]);
      await Poll.create({
        question: 'Which day should we hold the monthly RWA meeting?',
        options: JSON.stringify(['Saturday Morning', 'Sunday Morning', 'Sunday Evening', 'Weekday Evening']),
        endDate: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000), // 7 days
        societyId: defaultSocietyId,
        createdById: admin.id,
      });
      console.log('Seeded Notices and Polls.');
    }
  }

  // Seed parking slots
  const parkingCount = await ParkingSlot.count();
  if (parkingCount === 0 && defaultSocietyId) {
    const slots = [];
    // B1 floor: car slots
    for (let i = 1; i <= 10; i++) slots.push({ slotNumber: `B1-C${i.toString().padStart(2,'0')}`, type: 'car', floor: 'B1', societyId: defaultSocietyId });
    // B1 floor: bike slots
    for (let i = 1; i <= 6; i++) slots.push({ slotNumber: `B1-B${i.toString().padStart(2,'0')}`, type: 'bike', floor: 'B1', societyId: defaultSocietyId });
    // EV slots
    for (let i = 1; i <= 4; i++) slots.push({ slotNumber: `B1-EV${i.toString().padStart(2,'0')}`, type: 'ev', floor: 'B1', societyId: defaultSocietyId });
    await ParkingSlot.bulkCreate(slots);
    console.log('Seeded parking slots.');
  }
}).catch((err) => {
  console.error('Error syncing SQLite database:', err);
});

// Authentication middleware
const auth = async (req, res, next) => {
  try {
    const token = req.header('Authorization')?.replace('Bearer ', '');
    if (!token) throw new Error();

    const decoded = jwt.verify(token, process.env.JWT_SECRET || 'your-secret-key-here');
    const user = await User.findByPk(decoded.userId);
    if (!user) throw new Error();

    req.user = user;
    next();
  } catch (error) {
    res.status(401).send({ error: 'Please authenticate.' });
  }
};

// Routes
app.post('/api/register', async (req, res) => {
  try {
    const { email, password, name, role = 'resident', societyId, flatId } = req.body;
    const hashedPassword = await bcrypt.hash(password, 8);
    
    // Check if email exists
    const existingUser = await User.findOne({ where: { email } });
    if (existingUser) {
      return res.status(400).send({ error: 'Email already exists' });
    }

    let assignSocietyId = societyId;
    let assignFlatId = flatId;
    
    if (role !== 'super_admin') {
      // Assign to default Society/Flat if missing for MVP
      if (!assignSocietyId) {
        const defSociety = await Society.findOne();
        if (defSociety) assignSocietyId = defSociety.id;
      }
      if (!assignFlatId) {
        const defFlat = await Flat.findOne();
        if (defFlat) assignFlatId = defFlat.id;
      }
    }

    const user = await User.create({ 
      email, 
      password: hashedPassword, 
      name, 
      role,
      societyId: assignSocietyId || null,
      flatId: assignFlatId || null
    });
    
    const userJSON = user.toJSON();
    delete userJSON.password;
    res.status(201).send(userJSON);
  } catch (error) {
    res.status(400).send({ error: error.message });
  }
});

app.post('/api/login', async (req, res) => {
  try {
    const { email, password } = req.body;
    const user = await User.findOne({ where: { email } });
    if (!user) throw new Error('Invalid credentials');

    const isValidPassword = await bcrypt.compare(password, user.password);
    if (!isValidPassword) throw new Error('Invalid credentials');

    const token = jwt.sign({ userId: user.id }, process.env.JWT_SECRET || 'your-secret-key-here');
    const userJSON = user.toJSON();
    delete userJSON.password;
    res.send({ user: userJSON, token });
  } catch (error) {
    res.status(400).send({ error: error.message });
  }
});

// ===== TEST CONNECTION (NO AUTH) =====
app.get('/api/test', async (req, res) => {
  try {
    const { societyId } = req.query;
    if (!societyId) return res.status(400).send({ error: 'societyId required' });
    const society = await Society.findByPk(societyId);
    if (!society) return res.status(404).send({ error: 'Society not found' });
    res.send({ message: 'Connection successful', societyName: society.name });
  } catch (e) { res.status(500).send({ error: e.message }); }
});

// ===== PROFILE ENDPOINTS =====
app.put('/api/profile', auth, async (req, res) => {
  try {
    const { name, contactNumber, apartmentNumber } = req.body;
    await req.user.update({ name, contactNumber, apartmentNumber });
    const userJSON = req.user.toJSON();
    delete userJSON.password;
    res.send(userJSON);
  } catch (e) { res.status(400).send({ error: e.message }); }
});

app.put('/api/profile/password', auth, async (req, res) => {
  try {
    const { currentPassword, newPassword } = req.body;
    const isValid = await bcrypt.compare(currentPassword, req.user.password);
    if (!isValid) return res.status(400).send({ error: 'Current password is incorrect' });
    if (!newPassword || newPassword.length < 6) return res.status(400).send({ error: 'New password must be at least 6 characters' });
    req.user.password = await bcrypt.hash(newPassword, 8);
    await req.user.save();
    res.send({ message: 'Password changed successfully' });
  } catch (e) { res.status(400).send({ error: e.message }); }
});

// ===== ADMIN: USER MANAGEMENT =====
app.get('/api/admin/users', auth, async (req, res) => {
  try {
    if (req.user.role !== 'admin') return res.status(403).send({ error: 'Admin only' });
    const users = await User.findAll({
      where: { societyId: req.user.societyId },
      attributes: { exclude: ['password'] },
      order: [['name', 'ASC']],
    });
    res.send(users);
  } catch (e) { res.status(500).send({ error: e.message }); }
});

app.post('/api/admin/users', auth, async (req, res) => {
  try {
    if (req.user.role !== 'admin') return res.status(403).send({ error: 'Admin only' });
    const { name, email, password, role, contactNumber, apartmentNumber } = req.body;
    const existing = await User.findOne({ where: { email } });
    if (existing) return res.status(400).send({ error: 'Email already exists' });
    const hashed = await bcrypt.hash(password, 8);
    const defFlat = await Flat.findOne({ where: { societyId: req.user.societyId } });
    const user = await User.create({
      name, email, password: hashed, role: role || 'resident',
      contactNumber, apartmentNumber,
      societyId: req.user.societyId,
      flatId: defFlat?.id || null,
    });
    const userJSON = user.toJSON();
    delete userJSON.password;
    res.status(201).send(userJSON);
  } catch (e) { res.status(400).send({ error: e.message }); }
});

app.put('/api/admin/users/:id/role', auth, async (req, res) => {
  try {
    if (req.user.role !== 'admin') return res.status(403).send({ error: 'Admin only' });
    const target = await User.findByPk(req.params.id);
    if (!target) return res.status(404).send({ error: 'User not found' });
    if (target.id === req.user.id) return res.status(400).send({ error: 'Cannot change your own role' });
    target.role = req.body.role;
    await target.save();
    const userJSON = target.toJSON();
    delete userJSON.password;
    res.send(userJSON);
  } catch (e) { res.status(400).send({ error: e.message }); }
});

app.delete('/api/admin/users/:id', auth, async (req, res) => {
  try {
    if (req.user.role !== 'admin') return res.status(403).send({ error: 'Admin only' });
    const target = await User.findByPk(req.params.id);
    if (!target) return res.status(404).send({ error: 'User not found' });
    if (target.id === req.user.id) return res.status(400).send({ error: 'Cannot delete yourself' });
    await target.destroy();
    res.send({ message: 'User removed' });
  } catch (e) { res.status(400).send({ error: e.message }); }
});

// ===== ADMIN: SOCIETY SETTINGS =====
app.get('/api/admin/society', auth, async (req, res) => {
  try {
    if (req.user.role !== 'admin') return res.status(403).send({ error: 'Admin only' });
    const society = await Society.findByPk(req.user.societyId, {
      include: [{ model: Block, include: [{ model: Flat }] }],
    });
    if (!society) return res.status(404).send({ error: 'Society not found' });
    const data = society.toJSON();
    data.totalFlats = await Flat.count({ where: { societyId: req.user.societyId } });
    data.totalResidents = await User.count({ where: { societyId: req.user.societyId, role: 'resident' } });
    data.totalBlocks = await Block.count({ where: { societyId: req.user.societyId } });
    res.send(data);
  } catch (e) { res.status(500).send({ error: e.message }); }
});

app.put('/api/admin/society', auth, async (req, res) => {
  try {
    if (req.user.role !== 'admin') return res.status(403).send({ error: 'Admin only' });
    const society = await Society.findByPk(req.user.societyId);
    if (!society) return res.status(404).send({ error: 'Society not found' });
    const { name, address, city, registrationNumber } = req.body;
    await society.update({ name, address, city, registrationNumber });
    res.send(society);
  } catch (e) { res.status(400).send({ error: e.message }); }
});

// ===== QR CODE FOR RESIDENTS =====
app.get('/api/admin/qrcode', auth, async (req, res) => {
  try {
    if (req.user.role !== 'admin') return res.status(403).send({ error: 'Admin only' });
    const society = await Society.findByPk(req.user.societyId);
    if (!society) return res.status(404).send({ error: 'Society not found' });
    
    const serverUrl = process.env.RAILWAY_PUBLIC_DOMAIN 
      ? `https://${process.env.RAILWAY_PUBLIC_DOMAIN}`
      : `http://localhost:${process.env.PORT || 5000}`;
    
    const qrData = {
      serverUrl: serverUrl.replace('/api', ''),
      societyId: society.id,
      societyName: society.name
    };
    
    res.send(qrData);
  } catch (e) { res.status(500).send({ error: e.message }); }
});

// ===== SUPER ADMIN: PLATFORM MANAGEMENT =====
app.get('/api/super-admin/societies', auth, async (req, res) => {
  try {
    if (req.user.role !== 'super_admin') return res.status(403).send({ error: 'Super Admin only' });
    const societies = await Society.findAll();
    // Fetch stats for each
    const data = await Promise.all(societies.map(async (soc) => {
      const sData = soc.toJSON();
      sData.totalUsers = await User.count({ where: { societyId: soc.id } });
      return sData;
    }));
    res.send(data);
  } catch (e) { res.status(500).send({ error: e.message }); }
});

app.post('/api/super-admin/societies', auth, async (req, res) => {
  try {
    if (req.user.role !== 'super_admin') return res.status(403).send({ error: 'Super Admin only' });
    const { name, address, city, registrationNumber, subscriptionPlan } = req.body;
    const society = await Society.create({ name, address, city, registrationNumber, subscriptionPlan });
    res.status(201).send(society);
  } catch (e) { res.status(400).send({ error: e.message }); }
});

app.put('/api/super-admin/societies/:id', auth, async (req, res) => {
  try {
    if (req.user.role !== 'super_admin') return res.status(403).send({ error: 'Super Admin only' });
    const society = await Society.findByPk(req.params.id);
    if (!society) return res.status(404).send({ error: 'Society not found' });
    const { name, address, city, subscriptionStatus, subscriptionPlan } = req.body;
    await society.update({ name, address, city, subscriptionStatus, subscriptionPlan });
    res.send(society);
  } catch (e) { res.status(400).send({ error: e.message }); }
});

app.get('/api/super-admin/societies/:id/admins', auth, async (req, res) => {
  try {
    if (req.user.role !== 'super_admin') return res.status(403).send({ error: 'Super Admin only' });
    const admins = await User.findAll({
      where: { societyId: req.params.id, role: 'admin' },
      attributes: { exclude: ['password'] }
    });
    res.send(admins);
  } catch (e) { res.status(500).send({ error: e.message }); }
});

app.post('/api/super-admin/societies/:id/admins', auth, async (req, res) => {
  try {
    if (req.user.role !== 'super_admin') return res.status(403).send({ error: 'Super Admin only' });
    const { name, email, password, contactNumber } = req.body;
    const existing = await User.findOne({ where: { email } });
    if (existing) return res.status(400).send({ error: 'Email already exists' });
    
    // Create admin user for this society
    const hashed = await bcrypt.hash(password, 8);
    const adminUser = await User.create({
      name, email, password: hashed, role: 'admin',
      contactNumber, societyId: req.params.id
    });
    
    const userJSON = adminUser.toJSON();
    delete userJSON.password;
    res.status(201).send(userJSON);
  } catch (e) { res.status(400).send({ error: e.message }); }
});

app.delete('/api/super-admin/users/:id', auth, async (req, res) => {
  try {
    if (req.user.role !== 'super_admin') return res.status(403).send({ error: 'Super Admin only' });
    const target = await User.findByPk(req.params.id);
    if (!target) return res.status(404).send({ error: 'User not found' });
    await target.destroy();
    res.send({ message: 'User removed' });
  } catch (e) { res.status(400).send({ error: e.message }); }
});

app.post('/api/maintenance', auth, async (req, res) => {
  try {
    const requestData = {
      ...req.body,
      submittedById: req.user.id,
      societyId: req.user.societyId,
    };
    const maintenanceRequest = await MaintenanceRequest.create(requestData);
    res.status(201).send(maintenanceRequest);
  } catch (error) {
    res.status(400).send({ error: error.message });
  }
});

app.get('/api/maintenance', auth, async (req, res) => {
  try {
    const requests = await MaintenanceRequest.findAll({
      include: [
        { model: User, as: 'submittedBy', attributes: ['name', 'apartmentNumber'] },
        { model: User, as: 'assignedTo', attributes: ['name'] }
      ],
      order: [['createdAt', 'DESC']]
    });
    res.send(requests);
  } catch (error) {
    res.status(500).send({ error: error.message });
  }
});

// --- BILLING & PAYMENT APIs ---
app.get('/api/invoices', auth, async (req, res) => {
  try {
    let invoices;
    if (req.user.role === 'admin') {
      invoices = await Invoice.findAll({ where: { societyId: req.user.societyId }, include: [{ model: User, attributes: ['name', 'flatId'] }], order: [['createdAt', 'DESC']] });
    } else {
      invoices = await Invoice.findAll({ where: { residentId: req.user.id }, order: [['createdAt', 'DESC']] });
    }
    res.send(invoices);
  } catch (error) {
    res.status(500).send({ error: error.message });
  }
});

// Admin endpoint to generate bulk invoices
app.post('/api/invoices/generate', auth, async (req, res) => {
  try {
    if (req.user.role !== 'admin') throw new Error('Unauthorized');
    const { title, amount, taxAmount, dueDate } = req.body;
    const residents = await User.findAll({ where: { societyId: req.user.societyId, role: 'resident' } });

    const totalAmount = amount + (taxAmount || 0);
    const invoices = residents.map(r => ({
      title, amount, taxAmount, totalAmount, dueDate,
      residentId: r.id, societyId: req.user.societyId, status: 'unpaid'
    }));

    await Invoice.bulkCreate(invoices);
    res.status(201).send({ message: `Successfully generated ${invoices.length} invoices.` });
  } catch (error) {
    res.status(400).send({ error: error.message });
  }
});

app.post('/api/payments/razorpay/order', auth, async (req, res) => {
  try {
    const { invoiceId } = req.body;
    const invoice = await Invoice.findByPk(invoiceId);
    if (!invoice) throw new Error('Invoice not found');
    if (invoice.residentId !== req.user.id) throw new Error('Unauthorized');

    const options = {
      amount: invoice.totalAmount * 100, // amount in smallest currency unit
      currency: "INR",
      receipt: `receipt_inv_${invoice.id}`.substring(0, 40)
    };

    // If mock keys, we handle it gracefully
    let order_id = "order_mock_" + Math.random().toString(36).substring(7);
    if (process.env.RAZORPAY_KEY_ID && process.env.RAZORPAY_KEY_ID !== 'rzp_test_mock') {
      const order = await razorpay.orders.create(options);
      order_id = order.id;
    }

    const payment = await Payment.create({
      amount: invoice.totalAmount,
      invoiceId: invoice.id,
      residentId: req.user.id,
      status: 'pending',
      razorpayOrderId: order_id
    });

    res.json({ orderId: order_id, paymentId: payment.id, amount: options.amount, currency: "INR" });
  } catch (error) {
    res.status(500).send({ error: error.message });
  }
});

app.post('/api/payments/razorpay/verify', auth, async (req, res) => {
  try {
    const { paymentId, razorpay_payment_id, razorpay_signature, status } = req.body;
    
    const payment = await Payment.findByPk(paymentId);
    if (!payment) throw new Error('Payment record not found');

    const invoice = await Invoice.findByPk(payment.invoiceId);

    // Mock verification for MVP if no real keys
    if (status === 'success' || process.env.RAZORPAY_KEY_ID === 'rzp_test_mock') {
       payment.status = 'completed';
       payment.transactionId = razorpay_payment_id || `txn_mock_${Math.random()}`;
       payment.paymentDate = new Date();
       await payment.save();

       if (invoice) {
         invoice.status = 'paid';
         await invoice.save();
         // --- Auto Notification: payment confirmed ---
         await createNotification(req.user.id, req.user.societyId, '💰 Payment Successful', `Your payment of ₹${invoice.totalAmount} for "${invoice.title}" was successful.`, 'payment');
       }
       return res.send({ success: true, message: 'Payment verified and updated successfully.' });
    } else {
       payment.status = 'failed';
       await payment.save();
       return res.status(400).send({ success: false, error: 'Payment verification failed' });
    }
  } catch (error) {
    res.status(500).send({ error: error.message });
  }
});

// Remove old payments APIs (replaced by generic logic)
app.get('/api/dashboard', auth, async (req, res) => {
  try {
    const invoices = await Invoice.findAll({ where: { residentId: req.user.id } });
    const pendingInvoices = invoices.filter(i => i.status === 'unpaid' || i.status === 'overdue');
    const totalDues = pendingInvoices.reduce((acc, curr) => acc + curr.totalAmount, 0);
    
    // Default stats layout for MVP
    res.send({ 
      totalDues, 
      openComplaints: await MaintenanceRequest.count({ where: { submittedById: req.user.id, status: 'pending' } }),
      totalComplaints: await MaintenanceRequest.count({ where: { submittedById: req.user.id } })
    });
  } catch (error) {
    res.status(500).send({ error: error.message });
  }
});

// --- VISITOR APIs ---
app.post('/api/visitors/preapprove', auth, async (req, res) => {
  try {
    const passCode = Math.floor(100000 + Math.random() * 900000).toString(); // 6 digit OTP
    const visitor = await Visitor.create({
      ...req.body, // expects name, mobile, purpose, expectedEntry
      status: 'Approved',
      passCode,
      flatId: req.user.flatId || null,
      societyId: req.user.societyId || null,
      approvedById: req.user.id
    });
    res.status(201).send(visitor);
  } catch (error) {
    res.status(400).send({ error: error.message });
  }
});

app.get('/api/visitors', auth, async (req, res) => {
  try {
    let visitors;
    if (req.user.role === 'guard') {
      // Guards see visitors for the society
      visitors = await Visitor.findAll({
        where: { societyId: req.user.societyId },
        order: [['createdAt', 'DESC']],
        include: [{ model: Flat, attributes: ['number'] }]
      });
    } else {
      // Resident sees visitors for their flat
      visitors = await Visitor.findAll({
        where: { flatId: req.user.flatId },
        order: [['createdAt', 'DESC']]
      });
    }
    res.send(visitors);
  } catch (error) {
    res.status(500).send({ error: error.message });
  }
});

app.put('/api/visitors/:id/status', auth, async (req, res) => {
  try {
    const { status } = req.body; // e.g., 'Entered', 'Exited', 'Approved', 'Denied'
    const visitor = await Visitor.findByPk(req.params.id);
    if (!visitor) return res.status(404).send({ error: 'Visitor not found' });
    
    visitor.status = status;
    if (status === 'Entered') visitor.actualEntry = new Date();
    if (status === 'Exited') visitor.exitTime = new Date();
    
    await visitor.save();

    // --- Auto Notification: notify flat owner ---
    if (visitor.flatId) {
      const flatOwner = await User.findOne({ where: { flatId: visitor.flatId, role: 'resident' } });
      if (flatOwner) {
        const msgMap = {
          'Approved': { title: '✅ Visitor Approved', body: `${visitor.name} has been approved to enter your flat.` },
          'Denied':   { title: '❌ Visitor Denied',   body: `${visitor.name}'s entry has been denied.` },
          'Entered':  { title: '🔔 Visitor Entered',  body: `${visitor.name} has entered the premises.` },
          'Exited':   { title: '👋 Visitor Exited',   body: `${visitor.name} has exited the premises.` },
        };
        if (msgMap[status]) {
          await createNotification(flatOwner.id, flatOwner.societyId, msgMap[status].title, msgMap[status].body, 'visitor');
        }
      }
    }

    res.send(visitor);
  } catch (error) {
    res.status(400).send({ error: error.message });
  }
});

// ===== PHASE 3: DAILY HELP APIs =====
app.get('/api/help', auth, async (req, res) => {
  try {
    const help = await DailyHelp.findAll({
      where: { flatId: req.user.flatId },
      order: [['name', 'ASC']]
    });
    res.send(help);
  } catch (error) {
    res.status(500).send({ error: error.message });
  }
});

app.post('/api/help', auth, async (req, res) => {
  try {
    const helpEntry = await DailyHelp.create({
      ...req.body,
      flatId: req.user.flatId,
      societyId: req.user.societyId,
    });
    res.status(201).send(helpEntry);
  } catch (error) {
    res.status(400).send({ error: error.message });
  }
});

app.put('/api/help/:id', auth, async (req, res) => {
  try {
    const help = await DailyHelp.findByPk(req.params.id);
    if (!help) return res.status(404).send({ error: 'Not found' });
    await help.update(req.body);
    res.send(help);
  } catch (error) {
    res.status(400).send({ error: error.message });
  }
});

app.delete('/api/help/:id', auth, async (req, res) => {
  try {
    const help = await DailyHelp.findByPk(req.params.id);
    if (!help) return res.status(404).send({ error: 'Not found' });
    await help.destroy();
    res.send({ message: 'Removed' });
  } catch (error) {
    res.status(400).send({ error: error.message });
  }
});

app.post('/api/help/:id/attendance', auth, async (req, res) => {
  try {
    const { date, status, checkIn, checkOut } = req.body;
    const [record, created] = await HelpAttendance.findOrCreate({
      where: { helpId: req.params.id, date },
      defaults: { status, checkIn, checkOut, helpId: req.params.id }
    });
    if (!created) await record.update({ status, checkIn, checkOut });
    res.send(record);
  } catch (error) {
    res.status(400).send({ error: error.message });
  }
});

app.get('/api/help/:id/attendance', auth, async (req, res) => {
  try {
    const records = await HelpAttendance.findAll({
      where: { helpId: req.params.id },
      order: [['date', 'DESC']],
      limit: 30,
    });
    res.send(records);
  } catch (error) {
    res.status(500).send({ error: error.message });
  }
});

// ===== PHASE 3: AMENITY APIs =====
app.get('/api/amenities', auth, async (req, res) => {
  try {
    const amenities = await Amenity.findAll({
      where: { societyId: req.user.societyId },
      order: [['name', 'ASC']]
    });
    res.send(amenities);
  } catch (error) {
    res.status(500).send({ error: error.message });
  }
});

app.get('/api/amenities/:id/bookings', auth, async (req, res) => {
  try {
    const { date } = req.query;
    const where = { amenityId: req.params.id, status: 'confirmed' };
    if (date) where.bookingDate = date;
    const bookings = await AmenityBooking.findAll({
      where,
      include: [{ model: User, attributes: ['name', 'apartmentNumber'] }]
    });
    res.send(bookings);
  } catch (error) {
    res.status(500).send({ error: error.message });
  }
});

app.get('/api/bookings/my', auth, async (req, res) => {
  try {
    const bookings = await AmenityBooking.findAll({
      where: { bookedById: req.user.id },
      include: [{ model: Amenity, attributes: ['name', 'imageEmoji'] }],
      order: [['bookingDate', 'DESC']],
    });
    res.send(bookings);
  } catch (error) {
    res.status(500).send({ error: error.message });
  }
});

app.post('/api/amenities/:id/book', auth, async (req, res) => {
  try {
    const { bookingDate, startTime, endTime, notes } = req.body;
    const amenity = await Amenity.findByPk(req.params.id);
    if (!amenity) return res.status(404).send({ error: 'Amenity not found' });

    // Conflict check
    const conflict = await AmenityBooking.findOne({
      where: {
        amenityId: req.params.id,
        bookingDate,
        status: 'confirmed',
        startTime: { [Sequelize.Op.lt]: endTime },
        endTime: { [Sequelize.Op.gt]: startTime },
      }
    });
    if (conflict) return res.status(409).send({ error: 'Slot already booked. Please choose another time.' });

    // Calculate hours and price
    const [sh, sm] = startTime.split(':').map(Number);
    const [eh, em] = endTime.split(':').map(Number);
    const hours = ((eh * 60 + em) - (sh * 60 + sm)) / 60;
    const totalAmount = hours * amenity.pricePerHour;

    const booking = await AmenityBooking.create({
      amenityId: req.params.id,
      bookedById: req.user.id,
      bookingDate, startTime, endTime, notes,
      totalAmount,
    });
    // --- Auto Notification: booking confirmed ---
    await createNotification(req.user.id, req.user.societyId, '🏊 Amenity Booked', `Your booking for ${amenity.name} on ${bookingDate} (${startTime}–${endTime}) is confirmed.${totalAmount > 0 ? ` Amount: ₹${totalAmount}` : ''}`, 'amenity');
    res.status(201).send(booking);
  } catch (error) {
    res.status(400).send({ error: error.message });
  }
});

app.put('/api/bookings/:id/cancel', auth, async (req, res) => {
  try {
    const booking = await AmenityBooking.findByPk(req.params.id);
    if (!booking) return res.status(404).send({ error: 'Booking not found' });
    if (booking.bookedById !== req.user.id) return res.status(403).send({ error: 'Unauthorized' });
    booking.status = 'cancelled';
    await booking.save();
    res.send(booking);
  } catch (error) {
    res.status(400).send({ error: error.message });
  }
});

// ===== PHASE 4: NOTICES APIs =====
app.get('/api/notices', auth, async (req, res) => {
  try {
    const notices = await Notice.findAll({
      where: { societyId: req.user.societyId },
      include: [{ model: User, as: 'postedBy', attributes: ['name'] }],
      order: [['isPinned', 'DESC'], ['createdAt', 'DESC']],
    });
    res.send(notices);
  } catch (e) { res.status(500).send({ error: e.message }); }
});

app.post('/api/notices', auth, async (req, res) => {
  try {
    if (req.user.role !== 'admin') throw new Error('Only admins can post notices');
    const notice = await Notice.create({
      ...req.body,
      societyId: req.user.societyId,
      postedById: req.user.id,
    });
    res.status(201).send(notice);
  } catch (e) { res.status(400).send({ error: e.message }); }
});

app.delete('/api/notices/:id', auth, async (req, res) => {
  try {
    if (req.user.role !== 'admin') throw new Error('Unauthorized');
    const n = await Notice.findByPk(req.params.id);
    if (!n) return res.status(404).send({ error: 'Not found' });
    await n.destroy();
    res.send({ message: 'Deleted' });
  } catch (e) { res.status(400).send({ error: e.message }); }
});

// ===== PHASE 4: POLLS APIs =====
app.get('/api/polls', auth, async (req, res) => {
  try {
    const polls = await Poll.findAll({
      where: { societyId: req.user.societyId },
      include: [{ model: PollVote }],
      order: [['createdAt', 'DESC']],
    });
    // Add user's vote and tally counts
    const enriched = polls.map(p => {
      const pj = p.toJSON();
      pj.options = JSON.parse(pj.options);
      pj.voteCounts = pj.options.map((_, idx) => pj.PollVotes.filter(v => v.optionIndex === idx).length);
      pj.userVote = pj.PollVotes.find(v => v.userId === req.user.id)?.optionIndex ?? null;
      pj.totalVotes = pj.PollVotes.length;
      return pj;
    });
    res.send(enriched);
  } catch (e) { res.status(500).send({ error: e.message }); }
});

app.post('/api/polls/:id/vote', auth, async (req, res) => {
  try {
    const { optionIndex } = req.body;
    const existing = await PollVote.findOne({ where: { pollId: req.params.id, userId: req.user.id } });
    if (existing) return res.status(409).send({ error: 'You have already voted on this poll.' });
    const vote = await PollVote.create({ pollId: req.params.id, userId: req.user.id, optionIndex });
    res.status(201).send(vote);
  } catch (e) { res.status(400).send({ error: e.message }); }
});

// ===== PHASE 4: HELPDESK ESCALATION APIs =====
app.put('/api/maintenance/:id/escalate', auth, async (req, res) => {
  try {
    if (req.user.role !== 'admin') throw new Error('Only admins can escalate');
    const ticket = await MaintenanceRequest.findByPk(req.params.id);
    if (!ticket) return res.status(404).send({ error: 'Ticket not found' });
    ticket.status = 'escalated';
    ticket.priority = 'critical';
    ticket.escalatedAt = new Date();
    await ticket.save();
    res.send(ticket);
  } catch (e) { res.status(400).send({ error: e.message }); }
});

app.put('/api/maintenance/:id/resolve', auth, async (req, res) => {
  try {
    const ticket = await MaintenanceRequest.findByPk(req.params.id);
    if (!ticket) return res.status(404).send({ error: 'Ticket not found' });
    ticket.status = 'resolved';
    ticket.resolvedAt = new Date();
    await ticket.save();
    // --- Auto Notification: notify resident who submitted ---
    if (ticket.submittedById) {
      const submitter = await User.findByPk(ticket.submittedById);
      if (submitter) {
        await createNotification(submitter.id, submitter.societyId, '🔧 Issue Resolved', `Your complaint "${ticket.title}" has been resolved. Please rate the service.`, 'maintenance');
      }
    }
    res.send(ticket);
  } catch (e) { res.status(400).send({ error: e.message }); }
});

app.put('/api/maintenance/:id/rate', auth, async (req, res) => {
  try {
    const { rating, comment } = req.body;
    const ticket = await MaintenanceRequest.findByPk(req.params.id);
    if (!ticket) return res.status(404).send({ error: 'Ticket not found' });
    if (ticket.submittedById !== req.user.id) return res.status(403).send({ error: 'Unauthorized' });
    if (ticket.status !== 'resolved') return res.status(400).send({ error: 'Can only rate resolved tickets' });
    ticket.residentRating = rating;
    ticket.residentComment = comment;
    await ticket.save();
    res.send(ticket);
  } catch (e) { res.status(400).send({ error: e.message }); }
});

// ===== PHASE 4: IoT STUBS =====
app.post('/api/iot/barrier', auth, async (req, res) => {
  // Stub for boom barrier integration — in production this sends a signal via IoT gateway
  const { action, vehicleNo } = req.body; // action: 'open' | 'close'
  console.log(`[IoT] Barrier ${action} request for vehicle: ${vehicleNo} by user: ${req.user.name}`);
  res.send({ success: true, message: `Barrier ${action} command sent.`, vehicleNo, timestamp: new Date() });
});

app.post('/api/iot/lock', auth, async (req, res) => {
  // Stub for smart lock control — in production integrates with MQTT/Zigbee gateway
  const { flatId, action, method } = req.body; // action: 'unlock'|'lock', method: 'otp'|'app'
  console.log(`[IoT] Smart lock ${action} for flat ${flatId} via ${method} by ${req.user.name}`);
  res.send({ success: true, message: `Smart lock ${action} sent.`, otp: action === 'unlock' ? Math.floor(100000 + Math.random() * 900000) : null, timestamp: new Date() });
});

// ===== PHASE 5: PARKING APIs =====
app.get('/api/parking/slots', auth, async (req, res) => {
  try {
    const slots = await ParkingSlot.findAll({
      where: { societyId: req.user.societyId },
      order: [['type', 'ASC'], ['slotNumber', 'ASC']],
    });
    res.send(slots);
  } catch (e) { res.status(500).send({ error: e.message }); }
});

app.post('/api/parking/allocate', auth, async (req, res) => {
  try {
    if (req.user.role !== 'admin') throw new Error('Only admins can allocate parking');
    const { slotId, flatId, vehicleNo, vehicleType } = req.body;
    const slot = await ParkingSlot.findByPk(slotId);
    if (!slot) return res.status(404).send({ error: 'Slot not found' });
    if (slot.status !== 'available') return res.status(409).send({ error: 'Slot already occupied or reserved' });
    
    const allocation = await ParkingAllocation.create({
      slotId, flatId: flatId || null, vehicleNo, vehicleType,
      startDate: new Date().toISOString().split('T')[0],
      allocatedById: req.user.id,
    });
    slot.status = 'occupied';
    slot.vehicleNo = vehicleNo;
    await slot.save();
    res.status(201).send({ allocation, slot });
  } catch (e) { res.status(400).send({ error: e.message }); }
});

app.put('/api/parking/release/:slotId', auth, async (req, res) => {
  try {
    if (req.user.role !== 'admin') throw new Error('Only admins can release parking');
    const slot = await ParkingSlot.findByPk(req.params.slotId);
    if (!slot) return res.status(404).send({ error: 'Slot not found' });
    
    await ParkingAllocation.update(
      { isActive: false, endDate: new Date().toISOString().split('T')[0] },
      { where: { slotId: req.params.slotId, isActive: true } }
    );
    slot.status = 'available';
    slot.vehicleNo = null;
    await slot.save();
    res.send(slot);
  } catch (e) { res.status(400).send({ error: e.message }); }
});

// ===== PHASE 5: MARKETPLACE APIs =====
app.get('/api/marketplace', auth, async (req, res) => {
  try {
    const { category } = req.query;
    const where = { societyId: req.user.societyId, status: 'active' };
    if (category && category !== 'all') where.category = category;
    const listings = await MarketplaceListing.findAll({
      where,
      include: [{ model: User, as: 'seller', attributes: ['name', 'apartmentNumber'] }],
      order: [['createdAt', 'DESC']],
    });
    res.send(listings);
  } catch (e) { res.status(500).send({ error: e.message }); }
});

app.post('/api/marketplace', auth, async (req, res) => {
  try {
    const listing = await MarketplaceListing.create({
      ...req.body,
      societyId: req.user.societyId,
      sellerId: req.user.id,
      contactInfo: req.user.contactNumber || req.user.email,
    });
    res.status(201).send(listing);
  } catch (e) { res.status(400).send({ error: e.message }); }
});

app.put('/api/marketplace/:id/sold', auth, async (req, res) => {
  try {
    const listing = await MarketplaceListing.findByPk(req.params.id);
    if (!listing) return res.status(404).send({ error: 'Not found' });
    if (listing.sellerId !== req.user.id && req.user.role !== 'admin') return res.status(403).send({ error: 'Unauthorized' });
    listing.status = 'sold';
    await listing.save();
    res.send(listing);
  } catch (e) { res.status(400).send({ error: e.message }); }
});

app.delete('/api/marketplace/:id', auth, async (req, res) => {
  try {
    const listing = await MarketplaceListing.findByPk(req.params.id);
    if (!listing) return res.status(404).send({ error: 'Not found' });
    if (listing.sellerId !== req.user.id && req.user.role !== 'admin') return res.status(403).send({ error: 'Unauthorized' });
    listing.status = 'removed';
    await listing.save();
    res.send({ message: 'Listing removed' });
  } catch (e) { res.status(400).send({ error: e.message }); }
});

// ===== PHASE 5: ADVANCED REPORTS APIs =====
app.get('/api/reports/financial', auth, async (req, res) => {
  try {
    if (req.user.role !== 'admin') return res.status(403).send({ error: 'Admin only' });
    const allInvoices = await Invoice.findAll({ where: { societyId: req.user.societyId } });
    const paid = allInvoices.filter(i => i.status === 'paid');
    const unpaid = allInvoices.filter(i => i.status === 'unpaid');
    const overdue = allInvoices.filter(i => i.status === 'overdue');
    const totalBilled = allInvoices.reduce((s, i) => s + (i.totalAmount || 0), 0);
    const totalCollected = paid.reduce((s, i) => s + (i.totalAmount || 0), 0);
    const collectionRate = totalBilled > 0 ? ((totalCollected / totalBilled) * 100).toFixed(1) : 0;
    res.send({
      totalInvoices: allInvoices.length,
      paid: paid.length,
      unpaid: unpaid.length,
      overdue: overdue.length,
      totalBilled: totalBilled.toFixed(2),
      totalCollected: totalCollected.toFixed(2),
      totalOutstanding: (totalBilled - totalCollected).toFixed(2),
      collectionRate,
    });
  } catch (e) { res.status(500).send({ error: e.message }); }
});

app.get('/api/reports/maintenance', auth, async (req, res) => {
  try {
    if (req.user.role !== 'admin') return res.status(403).send({ error: 'Admin only' });
    const all = await MaintenanceRequest.findAll({ where: { societyId: req.user.societyId } });
    const byStatus = { pending: 0, in_progress: 0, resolved: 0, escalated: 0 };
    let totalResolutionMs = 0, resolvedCount = 0, totalRating = 0, ratedCount = 0;
    all.forEach(t => {
      byStatus[t.status] = (byStatus[t.status] || 0) + 1;
      if (t.resolvedAt && t.createdAt) { totalResolutionMs += new Date(t.resolvedAt) - new Date(t.createdAt); resolvedCount++; }
      if (t.residentRating) { totalRating += t.residentRating; ratedCount++; }
    });
    res.send({
      total: all.length,
      byStatus,
      avgResolutionHours: resolvedCount > 0 ? (totalResolutionMs / resolvedCount / 3600000).toFixed(1) : 'N/A',
      avgRating: ratedCount > 0 ? (totalRating / ratedCount).toFixed(1) : 'N/A',
    });
  } catch (e) { res.status(500).send({ error: e.message }); }
});

app.get('/api/reports/amenity', auth, async (req, res) => {
  try {
    if (req.user.role !== 'admin') return res.status(403).send({ error: 'Admin only' });
    const amenities = await Amenity.findAll({
      where: { societyId: req.user.societyId },
      include: [{ model: AmenityBooking, where: { status: 'confirmed' }, required: false }],
    });
    const report = amenities.map(a => ({
      name: a.name,
      emoji: a.imageEmoji,
      bookings: a.AmenityBookings?.length ?? 0,
      revenue: (a.AmenityBookings || []).reduce((s, b) => s + (b.totalAmount || 0), 0),
    }));
    res.send(report);
  } catch (e) { res.status(500).send({ error: e.message }); }
});

app.get('/api/reports/occupancy', auth, async (req, res) => {
  try {
    if (req.user.role !== 'admin') return res.status(403).send({ error: 'Admin only' });
    const totalFlats = await Flat.count({ where: { societyId: req.user.societyId } });
    const occupiedFlats = await User.count({ where: { societyId: req.user.societyId, role: 'resident' }, col: 'flatId', distinct: true });
    const totalResidents = await User.count({ where: { societyId: req.user.societyId, role: 'resident' } });
    const totalSlots = await ParkingSlot.count({ where: { societyId: req.user.societyId } });
    const occupiedSlots = await ParkingSlot.count({ where: { societyId: req.user.societyId, status: 'occupied' } });
    res.send({
      totalFlats, occupiedFlats, vacantFlats: totalFlats - occupiedFlats, totalResidents,
      parkingTotal: totalSlots, parkingOccupied: occupiedSlots, parkingAvailable: totalSlots - occupiedSlots,
      occupancyRate: totalFlats > 0 ? ((occupiedFlats / totalFlats) * 100).toFixed(1) : 0,
      parkingUtilization: totalSlots > 0 ? ((occupiedSlots / totalSlots) * 100).toFixed(1) : 0,
    });
  } catch (e) { res.status(500).send({ error: e.message }); }
});

// ===== SUPER ADMIN APIs =====

// GET global stats for Super Admin
app.get('/api/superadmin/stats', auth, async (req, res) => {
  try {
    if (req.user.role !== 'super_admin') return res.status(403).send({ error: 'Super Admin only' });
    
    const [societiesCount, usersCount, societies] = await Promise.all([
      Society.count(),
      User.count(),
      Society.findAll({ include: [PlatformInvoice] })
    ]);

    // Calculate MRR from active societies and total revenue from paid platform invoices
    let mrr = 0;
    let totalRevenue = 0;
    
    societies.forEach(s => {
      // MRR estimate
      if (s.subscriptionStatus === 'active') {
        if (s.subscriptionPlan === 'premium') mrr += 5000;
        else mrr += 2000;
      }
      // Total platform revenue
      (s.PlatformInvoices || []).forEach(inv => {
        if (inv.status === 'paid') totalRevenue += inv.amount;
      });
    });

    res.send({
      activeSocieties: societiesCount,
      totalUsers: usersCount,
      mrr: mrr.toFixed(2),
      totalRevenue: totalRevenue.toFixed(2),
      pendingInvoices: await PlatformInvoice.count({ where: { status: 'pending' } })
    });
  } catch (e) { res.status(500).send({ error: e.message }); }
});

// GET global settings and subscription plans
app.get('/api/superadmin/settings', auth, async (req, res) => {
  try {
    if (req.user.role !== 'super_admin') return res.status(403).send({ error: 'Super Admin only' });
    
    const settings = await PlatformSetting.findAll();
    const config = {};
    settings.forEach(s => {
      try { config[s.key] = JSON.parse(s.value); } 
      catch { config[s.key] = s.value; }
    });

    // Defaults if not set
    if (!config.plans) {
      config.plans = [
        { id: 'free', name: 'Free Trial', price: 0, features: ['Basic Visitor Mgmt', 'Complaints'] },
        { id: 'basic', name: 'Basic Tier', price: 2000, features: ['Unlimited Visitors', 'Billing', 'Staff Mgmt'] },
        { id: 'premium', name: 'Premium Tier', price: 5000, features: ['Amenities', 'Advanced Analytics', 'Parking Full Suite'] }
      ];
    }
    if (!config.payment) {
      config.payment = { razorpayKeyId: process.env.RAZORPAY_KEY_ID || '', gatewayActive: true };
    }

    res.send({
      platformName: config.platformName || 'SocietyHub',
      version: '1.0.0',
      maintenanceMode: config.maintenanceMode === 'true',
      supportEmail: config.supportEmail || 'support@societyhub.com',
      maxSocieties: 100,
      plans: config.plans,
      payment: config.payment
    });
  } catch (e) { res.status(500).send({ error: e.message }); }
});

// UPDATE global settings or plans
app.post('/api/superadmin/settings', auth, async (req, res) => {
  try {
    if (req.user.role !== 'super_admin') return res.status(403).send({ error: 'Super Admin only' });
    const { key, value } = req.body;
    
    await PlatformSetting.upsert({ 
      key, 
      value: typeof value === 'object' ? JSON.stringify(value) : String(value) 
    });
    
    res.send({ message: 'Settings updated' });
  } catch (e) { res.status(500).send({ error: e.message }); }
});

// GET all platform-level reports
app.get('/api/superadmin/reports', auth, async (req, res) => {
  try {
    if (req.user.role !== 'super_admin') return res.status(403).send({ error: 'Super Admin only' });
    
    // 1. Plan Distribution
    const societies = await Society.findAll({ include: [User, MaintenanceRequest, PlatformInvoice] });
    const planCounts = { free: 0, basic: 0, premium: 0 };
    
    // 2. Society-wise Breakdown
    const societyReports = societies.map(s => {
      planCounts[s.subscriptionPlan]++;
      const paidRev = (s.PlatformInvoices || []).reduce((acc, inv) => inv.status === 'paid' ? acc + inv.amount : acc, 0);
      return {
        id: s.id,
        name: s.name,
        city: s.city,
        plan: s.subscriptionPlan,
        users: s.Users?.length ?? 0,
        tickets: s.MaintenanceRequests?.length ?? 0,
        totalRevenue: paidRev.toFixed(2),
        status: s.subscriptionStatus
      };
    });

    // 3. Platform Growth Trends (Mocking historical for chart)
    const growth = [
      { month: 'Jan', users: 150, revenue: 12000, societies: 5 },
      { month: 'Feb', users: 280, revenue: 25000, societies: 8 },
      { month: 'Mar', users: await User.count(), revenue: 35000, societies: societies.length }
    ];

    res.send({ planDistribution: planCounts, societies: societyReports, growth });
  } catch (e) { res.status(500).send({ error: e.message }); }
});

// GET platform audit logs (mocked for MVP)
app.get('/api/superadmin/logs', auth, async (req, res) => {
  try {
    if (req.user.role !== 'super_admin') return res.status(403).send({ error: 'Super Admin only' });
    res.send([
      { id: 1, action: 'SOCIETY_CREATED', user: 'Admin', target: 'Grand Omaxe', timestamp: new Date() },
      { id: 2, action: 'PLAN_UPDATED', user: 'Admin', target: 'Premium', timestamp: new Date(Date.now() - 3600000) },
      { id: 3, action: 'GATEWAY_CONFIGURED', user: 'Admin', target: 'Razorpay', timestamp: new Date(Date.now() - 86400000) },
    ]);
  } catch (e) { res.status(500).send({ error: e.message }); }
});

// GET all society invoices (platform billing)
app.get('/api/superadmin/invoices', auth, async (req, res) => {
  try {
    if (req.user.role !== 'super_admin') return res.status(403).send({ error: 'Super Admin only' });
    const invoices = await PlatformInvoice.findAll({ include: [{ model: Society, attributes: ['name'] }] });
    res.send(invoices.map(inv => ({
      id: inv.id,
      societyName: inv.Society?.name || 'Unknown',
      amount: inv.amount,
      status: inv.status,
      date: inv.billingCycle || inv.createdAt
    })));
  } catch (e) { res.status(500).send({ error: e.message }); }
});

// ===== IN-APP NOTIFICATIONS APIs =====

// GET all notifications for the logged-in user
app.get('/api/notifications', auth, async (req, res) => {
  try {
    const notifications = await AppNotification.findAll({
      where: { userId: req.user.id },
      order: [['createdAt', 'DESC']],
      limit: 50,
    });
    res.send(notifications);
  } catch (e) { res.status(500).send({ error: e.message }); }
});

// GET unread count
app.get('/api/notifications/count', auth, async (req, res) => {
  try {
    const count = await AppNotification.count({ where: { userId: req.user.id, isRead: false } });
    res.send({ count });
  } catch (e) { res.status(500).send({ error: e.message }); }
});

// Mark a single notification as read
app.put('/api/notifications/:id/read', auth, async (req, res) => {
  try {
    const notif = await AppNotification.findOne({ where: { id: req.params.id, userId: req.user.id } });
    if (!notif) return res.status(404).send({ error: 'Not found' });
    notif.isRead = true;
    await notif.save();
    res.send(notif);
  } catch (e) { res.status(400).send({ error: e.message }); }
});

// Mark ALL notifications as read
app.put('/api/notifications/read-all', auth, async (req, res) => {
  try {
    await AppNotification.update({ isRead: true }, { where: { userId: req.user.id, isRead: false } });
    res.send({ message: 'All marked as read' });
  } catch (e) { res.status(400).send({ error: e.message }); }
});

app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

app.get('*', (req, res) => {
  res.json({ message: "SocietyHub API is running." });
});

// Start server - Railway provides $PORT env var
app.listen(PORT, HOST, () => {
  console.log(`Server running on http://${HOST}:${PORT}`);
});
